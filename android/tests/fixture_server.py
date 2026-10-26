"""Disposable emulator transport fixture; no real credentials or user text."""
from http.server import BaseHTTPRequestHandler, HTTPServer
import json
class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        length=int(self.headers.get('Content-Length','0'))
        if length>100000 or self.path!='/api/translate/text' or self.headers.get('X-API-Token')!='fixture-only':
            self.send_error(400);return
        data=json.loads(self.rfile.read(length));body=(json.dumps({'delta':'Translated: '+data['text']})+'\n'+json.dumps({'done':True})+'\n').encode()
        self.send_response(200);self.send_header('Content-Type','application/x-ndjson');self.send_header('Content-Length',str(len(body)));self.end_headers();self.wfile.write(body)
    def log_message(self,*args):pass
if __name__=='__main__':HTTPServer(('127.0.0.1',18325),Handler).serve_forever()
