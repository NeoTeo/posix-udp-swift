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
    sin_port:   htons(4242),
    sin_addr:   in_addr(s_addr: 0),
    sin_zero:   ( 0, 0, 0, 0, 0, 0, 0, 0 )
)

var responseSource: dispatch_source_t?

/// So htons casts to UInt16 and then turns into big endian (which is network byte order)
//let small = UInt16(1234)
//let swapped = small.bigEndian

func receiver(address: String, port: UInt16) -> dispatch_source_t? {
    /**
    1) Create a socket.
    2) Bind the socket.
    3) Connect the socket (optional).
    4) In a loop/separate thread/event listen for incoming packets.
    */
    var sockAddress = sockaddr_in(
        sin_len:    __uint8_t(sizeof(sockaddr_in)),
        sin_family: sa_family_t(AF_INET),
        sin_port:   htons(port),
        sin_addr:   in_addr(s_addr: 0),
        sin_zero:   ( 0, 0, 0, 0, 0, 0, 0, 0 )
    )

    /// inet_pton turns a text presentable ip to a network/binary representation
    address.withCString({ cs in inet_pton(AF_INET, cs, &sockAddress.sin_addr) })
    
    /// A socket file descriptor
    let sockFd = socket(PF_INET, SOCK_DGRAM, IPPROTO_UDP)
    
    guard sockFd >= 0  else {
        let errmsg = String.fromCString(strerror(errno))
        print("Error: Could not create socket. \(errmsg)")
        return nil
    }
    
    /// Bind the socket to the address
    let bindSuccess = withUnsafePointer(&sockAddress) {
        bind(sockFd, UnsafePointer($0), socklen_t( sizeofValue(sockAddress)))
    }
    
    guard bindSuccess == 0 else {
        let errmsg = String.fromCString(strerror(errno))
        print("Error: Could not bind socket! \(errmsg)")
        return nil
    }
    
    /// Connect. Since we're using UDP this isn't actually a connection but it does save us
    /// from having to restate the address when we want to use the socket.
    
/** 
    Enabling this causes the server to not receive any messages and appears to dump/deny any
    connections on the sockFd because when attempting to connect to it via the
    
        nc -u 127.0.0.1 4242 
    
    command it drops out immedately after sending the first message and it never arrives at
    the server, whereas when we don't call connect the nc command stays active and allows 
    subsequent messages to be sent.
    This issue took a good while to discover. :(
*/
    
//    let connectSuccess = withUnsafePointer(&sockAddress) {
//        connect(sockFd, UnsafePointer($0), socklen_t( sizeofValue(sockAddress)))
//    }
//    guard connectSuccess == 0 else {
//        let errmsg = String.fromCString(strerror(errno))    
//        print("Could not connect! \(errmsg)")
//        return nil
//    }
    
    /// Create a GCD thread that can listen for network events.
    guard let newResponseSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, UInt(sockFd), 0, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) else {
        let errmsg = String.fromCString(strerror(errno))
        print("dispatch_source_create failed. \(errmsg)")
        close(sockFd)
        return nil
    }
    
    /// Register the event handler for cancellation.
    dispatch_source_set_cancel_handler(newResponseSource) {
        let errmsg = String.fromCString(strerror(errno))
        print("Cancel handler \(errmsg)")
        close(sockFd)
    }
    
    
    /// Register the event handler for incoming packets.
    dispatch_source_set_event_handler(newResponseSource) {
        guard let source = responseSource else { return }
        
        var socketAddress = sockaddr_storage()
        var socketAddressLength = socklen_t(sizeof(sockaddr_storage.self))
        let response = [UInt8](count: 4096, repeatedValue: 0)
        let UDPSocket = Int32(dispatch_source_get_handle(source))

        let bytesRead = withUnsafeMutablePointer(&socketAddress) {
            recvfrom(UDPSocket, UnsafeMutablePointer<Void>(response), response.count, 0, UnsafeMutablePointer($0), &socketAddressLength)
        }

        let dataRead = response[0..<bytesRead]
        print("read \(bytesRead) bytes: \(dataRead)")
        if let dataString = String(bytes: dataRead, encoding: NSUTF8StringEncoding) {
            print("The message was: \(dataString)")
        }
    }
    
    dispatch_resume(newResponseSource)
    
    return newResponseSource
}

let ipPrefix    = "--ip="
let portPrefix  = "--port="

var target      = "none"
var port        = UInt16(4242)
var address     = "127.0.0.1"

for argNum in 1..<Process.arguments.count {
    switch Process.arguments[argNum] {
        case "server":
            target = "server"  
        case "client":
            target = "client"  
        case (let portval) where portval.hasPrefix(portPrefix):
            if let prefixRange = portval.rangeOfString(portPrefix) {
                port = UInt16(portval.substringFromIndex(prefixRange.endIndex))!
                print("port defined as \(port)")
            }
        case (let ipval) where ipval.hasPrefix(ipPrefix):
            if let prefixRange = ipval.rangeOfString(ipPrefix) {
                address = ipval.substringFromIndex(prefixRange.endIndex)
                print("ip address defined as \(address)")
            }
        default:
            print("Unknown argument: \(Process.arguments[argNum])") 
    }
}

switch target {
    case "server":
        print("Server starting")
        responseSource = receiver(address, port: port)
    case "client":
        print("Client starting")
        //sender()
    default:
        print("Usage: SockIt (server|client) [port] [ip]")
}

CFRunLoopRun()
