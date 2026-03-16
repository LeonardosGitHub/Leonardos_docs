
# Websockets and Forward Proxy - BIG-IP

### Install, verify, and test WebSockets with wscat via F5 Forward Proxy

#### Install wscat on Ubuntu
1. sudo apt-get update
2. sudo apt-get install -y --no-install-recommends ca-certificates node-ws

#### Verify installation
1. wscat --version

#### Test WebSocket directly (no proxy)

[NOTE] Websocket.org provides a public endpoint for ws testing: wss://echo.websocket.org/.ws

1. wscat -c wss://echo.websocket.org/.ws

- You should see:
	```
	Connected (press CTRL+C to quit)
		> hello
		< hello
	```

#### Test WebSocket through your F5 explicit proxy
1. Replace proxy IP/port with your forward proxy listener (example below):
	1. wscat -no-check --proxy http://10.1.1.1:3389 -c wss://echo.websocket.org/.ws
		1. -no-check = no certificate check


#### Success looks like:
```
ubuntu@ubuntu~$ wscat -no-check --proxy http://10.1.1.1:3389 -c wss://echo.websocket.org/.ws
Connected (press CTRL+C to quit)
< Request served by 4d896d95b55478
> testing
< testing
> test
< test
>
```


#### If you can't install wscat, use curl (kinda)

1. This will work but curl doesn't understand WS so you only get so far.
2. Replace the IP/port with your forward proxy listener (example below)
	1. curl -vvk --http1.1 --include --no-buffer --header "Connection: Upgrade" --header "Upgrade: websocket" --header "Sec-WebSocket-Key: <key_here>" --header "Sec-WebSocket-Version: 13" --proxy 10.1.1.1:3389 https://echo.websocket.org/.ws==


## Links to various docs

### BIG-IP
- 17.5: [Securing applications that use WebSocket connections](https://techdocs.f5.com/en-us/bigip-17-5-0/big-ip-asm-implementations/securing-applications-that-use-websocket.html)
- [K000132320: Overview of the Websocket profile](https://my.f5.com/manage/s/article/K000132320)
- [BIG-IP AWAF websocket youtube video](https://www.youtube.com/watch?v=p15hIdq0w0M)

### XC
- [K000147261: How to configure Websockets correctly on F5 XC platform?](https://my.f5.com/manage/s/article/K000147261)
- https://docs.cloud.f5.com/docs-v2/multi-cloud-app-connect/how-to/adv-security/configure-websocket

### Nginx
- TBD 


