# posix-udp-swift (SockIt)

> Simple project that shows how to make a simple UDP server and client in Swift using POSIX calls.

This project was an exploration of using the posix libraries from Swift by writing a UDP server/client.
Most of the complexity is in the bridging of Swift's type strictness to the C based Core Foundation libraries.

## Install

The project has no external dependencies.
To build, type:
`swift build`

The resulting binary will be in the default location:
`.build/debug/posix-udp-swift`

## Usage

Run the binary with appropriate args.
Run without args to get help.

## Examples

To start an UDP server that listens on localhost, port 1234:

`posix-udp-swift server --ip=127.0.0.1 --port=1234`

To start an UDP client that sends to localhost, port 1234:

`posix-udp-swift client --ip=127.0.0.1 --port=1234`


## Requirements

Swift 3.1

## License
[MIT](LICENSE)
