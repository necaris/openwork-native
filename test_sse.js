const { spawn } = require('child_process');
const http = require('http');

const server = spawn('opencode', ['serve', '--port', '8768']);

setTimeout(() => {
  const req = http.request({
    hostname: 'localhost',
    port: 8768,
    path: '/session',
    method: 'POST',
    headers: {'Content-Type': 'application/json'}
  }, (res) => {
    let data = '';
    res.on('data', d => data += d);
    res.on('end', () => {
      const session = JSON.parse(data);
      console.log('Session:', session.id);
      
      const sseReq = http.request({
        hostname: 'localhost',
        port: 8768,
        path: '/event',
        method: 'GET'
      }, (sseRes) => {
        sseRes.on('data', d => console.log('SSE:', d.toString()));
      });
      sseReq.end();
      
      setTimeout(() => {
        const promptReq = http.request({
          hostname: 'localhost',
          port: 8768,
          path: '/session/' + session.id + '/prompt_async',
          method: 'POST',
          headers: {'Content-Type': 'application/json'}
        });
        promptReq.write(JSON.stringify({parts: [{type: 'text', text: 'say hi in 1 word'}]}));
        promptReq.end();
      }, 500);
      
      setTimeout(() => {
        server.kill();
        process.exit(0);
      }, 4000);
    });
  });
  req.write(JSON.stringify({title: 'Test'}));
  req.end();
}, 2000);
