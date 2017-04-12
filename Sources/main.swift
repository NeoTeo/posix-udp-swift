

import Foundation /// Used for CFRunLoop
import Darwin
import Dispatch

public protocol SocketAddress {
    
}

/// Workaround Swift not having access to the C macros.
let isLittleEndian = Int(OSHostByteOrder()) == OSLittleEndian

/// Host to Network byte order small (2 bytes), large (4 bytes), large large (8 bytes)
let htons  = isLittleEndian ? _OSSwapInt16 : { $0 }
let htonl  = isLittleEndian ? _OSSwapInt32 : { $0 }
let htonll = isLittleEndian ? _OSSwapInt64 : { $0 }

/// Network byte order to host, small, etc.
let ntohs  = isLittleEndian ? _OSSwapInt16 : { $0 }
let ntohl  = isLittleEndian ? _OSSwapInt32 : { $0 }
let ntohll = isLittleEndian ? _OSSwapInt64 : { $0 }


let INETADDRESS_ANY = in_addr(s_addr: 0)

//var sockAddress = sockaddr_in(
//    sin_len:    __uint8_t(sizeof(sockaddr_in)),
//    sin_family: sa_family_t(AF_INET),
//    sin_port:   htons(4242),
//    sin_addr:   in_addr(s_addr: 0),
//    sin_zero:   ( 0, 0, 0, 0, 0, 0, 0, 0 )
//)

var responseSource: DispatchSourceRead? //dispatch_source_t?



//func receiver(address: String, port: UInt16) -> dispatch_source_t? {
func receiver(address: String, port: UInt16) -> DispatchSourceRead? {
    /**
    1) Create a socket.
    2) Bind the socket.
    3) Connect the socket (optional).
    4) In a loop/separate thread/event listen for incoming packets.
    */
    var sockAddress = sockaddr_in(
//        sin_len:    __uint8_t(sizeof(sockaddr_in)),
        sin_len:    __uint8_t(MemoryLayout<sockaddr_in>.size),
        sin_family: sa_family_t(AF_INET),
        sin_port:   htons(port),
        sin_addr:   in_addr(s_addr: 0),
        sin_zero:   ( 0, 0, 0, 0, 0, 0, 0, 0 )
    )

    /// inet_pton turns a text presentable ip to a network/binary representation
    _ = address.withCString({ cs in inet_pton(AF_INET, cs, &sockAddress.sin_addr) })
    
    /// A socket file descriptor
    let sockFd = socket(PF_INET, SOCK_DGRAM, IPPROTO_UDP)
    
    guard sockFd >= 0  else {
        let errmsg = String(cString: strerror(errno))
        print("Error: Could not create socket. \(errmsg)")
        return nil
    }
    
    /// Bind the socket to the address
    let bindSuccess = withUnsafePointer(to: &sockAddress) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1, { ptrSockAddress in
            bind(sockFd, ptrSockAddress, socklen_t( MemoryLayout<sockaddr>.size) )
        })
    }
    
    guard bindSuccess == 0 else {
        let errmsg = String(cString: strerror(errno))
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
    let newResponseSource = DispatchSource.makeReadSource(fileDescriptor: sockFd)
    
    newResponseSource.setCancelHandler {
        let errmsg = String(cString: strerror(errno))
        print("Cancel handler \(errmsg)")
        close(sockFd)
    }
    
    newResponseSource.setEventHandler {
        print("event!")
        guard let source = responseSource else { return }
        
        let addr = UnsafeMutablePointer<sockaddr_storage>.allocate(capacity: 1)
        let addrSockAddr = UnsafeMutablePointer<sockaddr>(OpaquePointer(addr))
        var socketAddressLength = socklen_t(MemoryLayout<sockaddr_storage>.size)
        let response = [UInt8](repeating: 0, count: 4096)
        let UDPSocket = Int32(source.handle)
        
        let bytesRead = recvfrom(UDPSocket,
                                 UnsafeMutableRawPointer(mutating: response),
                                 response.count,
                                 0,
                                 addrSockAddr,
                                 &socketAddressLength)
        
        let dataRead = response[0..<bytesRead]
        print("read \(bytesRead) bytes: \(dataRead)")
        if let dataString = String(bytes: dataRead, encoding: String.Encoding.utf8) {
            print("The message was: \(dataString)")
        }
    }
    
    newResponseSource.resume()
    
    return newResponseSource
}

func sender(address: String, port: UInt16) {
    
    var sockAddress = sockaddr_in(
        sin_len:    __uint8_t( MemoryLayout<sockaddr_in>.size ),
        sin_family: sa_family_t(AF_INET),
        sin_port:   htons(port),
        sin_addr:   in_addr(s_addr: 0),
        sin_zero:   ( 0, 0, 0, 0, 0, 0, 0, 0 )
    )

    /// inet_pton turns a text presentable ip to a network/binary representation
    _ = address.withCString({ cs in inet_pton(AF_INET, cs, &sockAddress.sin_addr) })

    /// A file descriptor Int32
    let sockFd = socket(PF_INET, SOCK_DGRAM, IPPROTO_UDP)
    
    guard sockFd >= 0  else {
        let errmsg = String(cString: strerror(errno))
        print("Error: Could not create socket. \(errmsg)")
        return
    }

    let outData = Array("Greetings earthling".utf8)

    let sent = withUnsafePointer(to: &sockAddress) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { ptrSockAddr in
            sendto(sockFd, outData, outData.count, 0, ptrSockAddr, socklen_t(sockAddress.sin_len))
        }
    }
    
    if sent == -1 {
        let errmsg = String(cString: strerror(errno))
        print("sendto failed: \(errno) \(errmsg)")
        return
    }
    
    print("Just sent \(sent) bytes as \(outData)")
    
    close(sockFd)
}

let ipPrefix    = "--ip="
let portPrefix  = "--port="

var target      = "none"
var port        = UInt16(4242)
var address     = "127.0.0.1"

/// Strip app name.
guard let appPath = CommandLine.arguments.first else { fatalError("Fatal! No app name.") }

let appName = appPath.components(separatedBy: "/").last ?? "SockIt"

for arg in CommandLine.arguments.dropFirst() {
    
    switch arg {
        
        case "server":
            target = "server"
        
        case "client":
            target = "client"
        
        case (let portval) where portval.hasPrefix(portPrefix):

            if let prefixRange = portval.range(of: portPrefix) {
                
                port = UInt16(portval.substring(from: prefixRange.upperBound))!
                
                print("port defined as \(port)")
            }
        
        case (let ipval) where ipval.hasPrefix(ipPrefix):

            if let prefixRange = ipval.range(of: ipPrefix) {

                address = ipval.substring(from: prefixRange.upperBound)
                print("ip address defined as \(address)")
            }
        
        default:
 
            print("Unknown argument: \(CommandLine.argc): \(CommandLine.arguments)")

    }
}

switch target {
    case "server":
        print("Server starting")
        responseSource = receiver(address: address, port: port)
        CFRunLoopRun()
    case "client":
        print("Client starting")
        sender(address: address, port: port)
    default:
        print("Usage: \(appName) (server|client) [--port=<portnumber>] [--ip=<address>]")
}

