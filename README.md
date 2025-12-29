
# zdir

static web server index written in Zig

## how to use

The project ships multiple versions:
- http
    - a standalone web server to server reqests
- cgi
    - CGI binary
- fcgi
    - FastCGI Service via a unix socket

Options:
- `-Droot=<path>` choose root path (default ".")
- `-Dport=<num>` select HTTP server port (default: 8888)
- `-Denable-lockdown=<bool>` whether to enable lockdown mode (capsicum on FreeBSD, landlock on Linux, default: yes)
- `-Dforce-lockdown=<bool>` if lockdown is required for the program to run (default: no)
- `-Dfcgi-socket-path=<path>` path for the FastCGI socket

## license
this project is licensed under the [MIT License](LICENSE)  
