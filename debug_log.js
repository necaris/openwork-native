const { spawn } = require('child_process');
const http = require('http');

const server = spawn('opencode', ['serve', '--port', '8771']);

setTimeout(() => {
  const req = http.request({
    hostname: 'localhost',
    port: 8771,
    path: '/session',
    method: 'POST',
    headers: {'Content-Type': 'application/json'}
  }, (res) => {
    let data = '';
    res.on('data', d => data += d);
    res.on('end', () => {
      const session = JSON.parse(data);
      
      const sseReq = http.request({
        hostname: 'localhost',
        port: 8771,
        path: '/event',
        method: 'GET'
      }, (sseRes) => {
        sseRes.on('data', d => {
            const str = d.toString();
            if (str.includes('message.updated') || str.includes('message.part')) {
                console.log(str.trim());
            }
        });
      });
      sseReq.end();
      
      setTimeout(() => {
        const promptReq = http.request({
          hostname: 'localhost',
          port: 8771,
          path: '/session/' + session.id + '/prompt_async',
          method: 'POST',
          headers: {'Content-Type': 'application/json'}
        });
        promptReq.write(JSON.stringify({parts: [{type: 'text', text: 'hi'}]}));
        promptReq.end();
      }, 500);
      
      setTimeout(() => {
        server.kill();
        process.exit(0);
      }, 3000);
    });
  });
  req.write(JSON.stringify({title: 'Test'}));
  req.end();
}, 2000);
