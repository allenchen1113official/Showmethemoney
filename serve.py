import http.server, os
os.chdir("/Users/allenchen/Library/CloudStorage/GoogleDrive-allenchen1113.official@gmail.com/我的雲端硬碟/Showmethemoney")
http.server.test(HandlerClass=http.server.SimpleHTTPRequestHandler, port=8765, bind="127.0.0.1")
