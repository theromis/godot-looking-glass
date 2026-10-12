"""Local protocol fixture, deliberately not a hardware emulator."""
from http.server import BaseHTTPRequestHandler, HTTPServer
import json
class Handler(BaseHTTPRequestHandler):
    def do_PUT(self):
        body=json.loads(self.rfile.read(int(self.headers.get('Content-Length','0'))))
        if self.path=='/enter_orchestration':
            data={'orchestration':{'value':body['name']},'payload':{'value':'fixture-token'}}
        elif body.get('orchestration')!='fixture-token':
            self.send_error(403); return
        elif self.path=='/available_output_devices':
            calibration={'screenW':{'value':1536},'screenH':{'value':2048},'viewCone':{'value':40}}
            data={'payload':{'value':{'0':{'value':{'calibration':{'value':json.dumps(calibration)}}}}}}
        else: data={'payload':{'value':True}}
        encoded=json.dumps(data).encode();self.send_response(200);self.send_header('Content-Type','application/json');self.send_header('Content-Length',str(len(encoded)));self.end_headers();self.wfile.write(encoded)
HTTPServer(('127.0.0.1',33335),Handler).serve_forever()
