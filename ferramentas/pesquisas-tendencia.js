const DATA_URL = 'data/trends.json';

function montarLinks(termo) {
    const q = encodeURIComponent(termo);
    return `
        <a class="google" href="https://www.google.com/search?q=${q}" target="_blank" title="Google">Google</a>
        <a class="bing" href="https://www.bing.com/search?q=${q}" target="_blank" title="Bing">Bing</a>
        <a class="yahoo" href="https://search.yahoo.com/search?p=${q}" target="_blank" title="Yahoo">Yahoo</a>
        <a class="duck" href="https://duckduckgo.com/?q=${q}" target="_blank" title="DuckDuckGo">DDG</a>
        <a class="brave" href="https://search.brave.com/search?q=${q}" target="_blank" title="Brave">Brave</a>
    `;
}

async function buscarTendencias() {
    const status = document.getElementById('status');
    const tabela = document.getElementById('tabela');
    const corpo = document.getElementById('corpo');
    const btn = document.getElementById('btnAtualizar');
    const pais = document.getElementById('pais').value;
    const idioma = document.getElementById('idioma').value;

    btn.disabled = true;
    btn.textContent = 'Carregando...';
    status.style.display = 'block';
    status.className = '';
    status.textContent = 'Buscando tendencias atuais...';
    tabela.style.display = 'none';
    corpo.innerHTML = '';

    try {
        const resp = await fetch(DATA_URL + '?t=' + Date.now());
        if (!resp.ok) throw new Error('Arquivo de dados nao encontrado');

        const data = await resp.json();
        let terms = data.terms || [];

        if (pais !== 'global') {
            terms = terms.filter(t => t.geo === pais);
        }

        if (terms.length === 0) {
            throw new Error('Nenhum termo encontrado para este pais');
        }

        terms.sort((a, b) => {
            const parseVol = (v) => {
                if (typeof v !== 'string') return 0;
                const n = parseFloat(v.replace(/[+,.]/g, ''));
                if (v.includes('M')) return n * 1000000;
                if (v.includes('K') || v.includes('k')) return n * 1000;
                return n;
            };
            return parseVol(b.volume) - parseVol(a.volume);
        });

        terms.forEach((termo, i) => {
            const tr = document.createElement('tr');
            tr.innerHTML = `
                <td class="rank">${i + 1}</td>
                <td class="keyword">${termo.titulo}</td>
                <td><span class="category">${termo.categoria}</span></td>
                <td class="traffic">${termo.volume}</td>
                <td class="engines">${montarLinks(termo.titulo)}</td>
            `;
            corpo.appendChild(tr);
        });

        const dt = new Date(data.updated);
        status.className = '';
        status.style.display = 'block';
        status.textContent = `Dados de ${dt.toLocaleDateString('pt-BR')} ${dt.toLocaleTimeString('pt-BR', {hour:'2-digit', minute:'2-digit'})} (fonte: ${data.source || 'cache'}) — ${terms.length} termos`;
        tabela.style.display = 'table';

    } catch (err) {
        status.className = 'error';
        status.textContent = 'Erro: ' + err.message + '. Clique em "Buscar Tendencias" para atualizar os dados.';
    } finally {
        btn.disabled = false;
        btn.textContent = 'Buscar Tendencias';
    }
}

function pesquisarManual() {
    const input = document.getElementById('buscaManual');
    const termo = input.value.trim();
    if (!termo) return;
    window.open('https://www.google.com/search?q=' + encodeURIComponent(termo), '_blank');
    input.value = '';
}

buscarTendencias();
