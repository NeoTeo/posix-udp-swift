//: Playground - noun: a place where people can play

import Foundation /// Used for CFRunLoop
import Darwin
import Dispatch

public protocol SocketAddress {
    
}

/// Workaround Swift not having access to the C macros.
let isLittleEndian = Int(OSHostByteOrder()) == OSLittleEndian

let htons  = isLittleEndian ? _OSSwapInt16 : { $0 }
let htonl  = isLittleEndian ? _OSSwapInt32 : { $0 }
let htonll = isLittleEndian ? _OSSwapInt64 : { $0 }
let ntohs  = isLittleEndian ? _OSSwapInt16 : { $0 }
let ntohl  = isLittleEndian ? _OSSwapInt32 : { $0 }
let ntohll = isLittleEndian ? _OSSwapInt64 : { $0 }


let INETADDRESS_ANY = in_addr(s_addr: 0)

var sockAddress = sockaddr_in(
    sin_len:    __uint8_t(sizeof(sockaddr_in)),
    sin_family: sa_family_t(AF_INET),
    /// no htons since it's implemented as a macro and Swift doesn't support C macros.
    sin_port:   htons(1337),
    sin_addr:   in_addr(s_addr: 0),
    sin_zero:   ( 0, 0, 0, 0, 0, 0, 0, 0 )
)

/// So htons casts to UInt16 and then turns into big endian (which is network byte order)
//let small = UInt16(1234)
//let swapped = small.bigEndian

func receiver() {
    /** 
        1) Create a socket.
        2) Bind the socket.
        3) Connect the socket (optional).
        4) In a loop/separate thread/event listen for incoming packets.
     */
     
    /// A file descriptor Int32
    let sock = socket(PF_INET, SOCK_DGRAM, IPPROTO_UDP)

    guard sock >= 0  else { print("That socks!") ; return }

    let lochost = "127.0.0.1".withCString({ cs in inet_pton(AF_INET, cs, &sockAddress.sin_addr) }) 

    /// Bind the socket to the address
    let boundSocketAddress = withUnsafePointer(&sockAddress) {
        bind(sock, UnsafePointer($0), socklen_t( sizeofValue(sockAddress)))
    }
    
    if boundSocketAddress != 0 {
        print("Could not bind socket!")
        return
    }

    /// Connect. Since we're using UDP this isn't actually a connection but it does save us
    /// from having to restate the address when we want to use the socket.
    let connectedSocketAddress = withUnsafePointer(&sockAddress) {
        connect(sock, UnsafePointer($0), socklen_t( sizeofValue(sockAddress)))
    }
    if connectedSocketAddress != 0 {
        print("Could not connect!")
        return
    }
    print("The connected socket \(connectedSocketAddress)")

    var socketAddress = sockaddr_storage()
    var socketAddressLength = socklen_t(sizeof(sockaddr_storage.self))
    print("SocketAddressLength \(socketAddressLength)")
    var buf = Array<UInt8>(count: 2048, repeatedValue: 0)
   
    /// Create a GCD thread that can listen for network events.
    guard let newResponseSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, UInt(sock), 0, dispatch_get_main_queue()) else {
        close(sock)
        return 
    }

    dispatch_source_set_cancel_handler(newResponseSource) {
        print("Cancel handler")
        close(sock)
    }

    dispatch_source_set_event_handler(newResponseSource) {
        print("Event!")
        let bytesRead = withUnsafeMutablePointer(&sockAddress) {
            recvfrom(sock, UnsafeMutablePointer<Void>(buf), buf.count, 0, UnsafeMutablePointer($0), &socketAddressLength)
        }
        print("bytes read \(bytesRead)")
    }

    print("Listening...")
    dispatch_resume(newResponseSource)

    CFRunLoopRun()
    print("Done")
}

print("Let's go")
receiver()

