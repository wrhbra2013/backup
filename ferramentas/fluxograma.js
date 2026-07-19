const templates = {
  simple: `graph TD
    A[Inicio] --> B{Decisao?}
    B -->|Sim| C[Acao 1]
    B -->|Nao| D[Acao 2]
    C --> E[Processar]
    D --> E
    E --> F[Fim]`,

  login: `graph TD
    A[Tela de Login] --> B{Credenciais}
    B -->|Validas| C[Carregar Perfil]
    B -->|Invalidas| D[Mostrar Erro]
    D --> A
    C --> E{2FA Ativo?}
    E -->|Sim| F[Solicitar Codigo]
    E -->|Nao| G[Dashboard]
    F --> H{Codigo Correto?}
    H -->|Sim| G
    H -->|Nao| I[Bloquear Conta]
    H -->|Timeout| A`,

  approval: `graph TD
    A[Enviar Pedido] --> B[Revisao do Gestor]
    B --> C{Aprovado?}
    C -->|Sim| D[Revisao Financeira]
    C -->|Reprovado| E[Notificar Rejeicao]
    D --> F{Limite OK?}
    F -->|Sim| G[Dir Executivo]
    F -->|Nao| D
    G --> H{Aprovado?}
    H -->|Sim| I[Pedido Confirmado]
    H -->|Nao| J[Escalacao]
    I --> K[Envio]
    J --> L[Revisao Manual]`,

  loop: `graph TD
    A[Inicio do Loop] --> B[Inicializar i = 0]
    B --> C{i < 10?}
    C -->|Sim| D[Processar item i]
    D --> E[i = i + 1]
    E --> C
    C -->|Nao| F[Retornar Resultados]
    F --> G[Fim]`,

  deploy: `graph TD
    A[Commit no Git] --> B[CI Trigger]
    B --> C[Instalar Dependencias]
    C --> D[Lint e Formatacao]
    D --> E{Erros?}
    E -->|Sim| F[Notificar Dev]
    E -->|Nao| G[Executar Testes]
    G --> H{Testes OK?}
    H -->|Nao| F
    H -->|Sim| I[Build de Producao]
    I --> J[Deploy Staging]
    J --> K[Testes E2E]
    K --> L{Aprovado?}
    L -->|Sim| M[Deploy Producao]
    L -->|Nao| F
    M --> N[Monitoramento]`,

  algorithm: `graph TD
    A[Vetor: 5,3,8,1,9] --> B[i = 0]
    B --> C{i < 4?}
    C -->|Sim| D[j = 0]
    D --> E{j < 4-i?}
    E -->|Sim| F{v[j] > v[j+1]?}
    F -->|Sim| G[Trocar v[j] e v[j+1]]
    F -->|Nao| H[j = j + 1]
    G --> H
    H --> E
    E -->|Nao| I[i = i + 1]
    I --> C
    C -->|Nao| J[Vetor Ordenado]`,

  flowchart_lr: `graph LR
    A[Entrada] --> B[Validacao]
    B --> C[Transformacao]
    C --> D[Armazenamento]
    D --> E[Resposta]
    B -->|Erro| F[Log de Erro]
    F --> G[Notificacao]`,

  subgraph: `graph TD
    subgraph Frontend
        A[React App] --> B[State Management]
        B --> C[API Client]
    end
    subgraph Backend
        D[API Gateway] --> E[Auth Service]
        E --> F[Business Logic]
        F --> G[Database]
    end
    C --> D
    G --> H[Cache Redis]
    H --> C`
  };

  let currentZoom = 1;

  mermaid.initialize({
    startOnLoad: false,
    theme: 'dark',
    themeVariables: {
      primaryColor: '#7b2ff7',
      primaryTextColor: '#fff',
      primaryBorderColor: '#00d2ff',
      lineColor: '#00d2ff',
      secondaryColor: '#1e1e3a',
      tertiaryColor: '#0f0c29',
      fontFamily: 'Segoe UI, sans-serif',
      fontSize: '14px'
    },
    flowchart: {
      htmlLabels: true,
      curve: 'basis',
      padding: 20,
      nodeSpacing: 50,
      rankSpacing: 60
    }
  });

  let idCounter = 0;

  async function renderChart() {
    const code = document.getElementById('codeEditor').value.trim();
    const output = document.getElementById('mermaidOutput');
    const errorEl = document.getElementById('errorMsg');

    errorEl.classList.remove('visible');

    if (!code) {
      errorEl.textContent = 'Digite algo para renderizar.';
      errorEl.classList.add('visible');
      return;
    }

    try {
      idCounter++;
      const { svg } = await mermaid.render(`mermaid-${idCounter}`, code);
      output.innerHTML = svg;
    } catch (err) {
      errorEl.textContent = 'Erro de sintaxe: ' + (err.message || 'Verifique o codigo Mermaid.');
      errorEl.classList.add('visible');
    }
  }

  function exportPNG() {
    const svg = document.querySelector('#mermaidOutput svg');
    if (!svg) {
      renderChart();
      return;
    }

    const svgData = new XMLSerializer().serializeToString(svg);
    const canvas = document.createElement('canvas');
    const ctx = canvas.getContext('2d');
    const img = new Image();

    const svgBlob = new Blob([svgData], { type: 'image/svg+xml;charset=utf-8' });
    const url = URL.createObjectURL(svgBlob);

    img.onload = function() {
      canvas.width = img.width * 2;
      canvas.height = img.height * 2;
      ctx.scale(2, 2);
      ctx.fillStyle = '#1a1a2e';
      ctx.fillRect(0, 0, img.width, img.height);
      ctx.drawImage(img, 0, 0);
      URL.revokeObjectURL(url);

      const a = document.createElement('a');
      a.download = 'fluxograma.png';
      a.href = canvas.toDataURL('image/png');
      a.click();
    };
    img.src = url;
  }

  function exportSVG() {
    const svg = document.querySelector('#mermaidOutput svg');
    if (!svg) {
      renderChart();
      return;
    }

    const svgData = new XMLSerializer().serializeToString(svg);
    const blob = new Blob([svgData], { type: 'image/svg+xml;charset=utf-8' });
    const a = document.createElement('a');
    a.download = 'fluxograma.svg';
    a.href = URL.createObjectURL(blob);
    a.click();
    URL.revokeObjectURL(a.href);
  }

  function clearEditor() {
    document.getElementById('codeEditor').value = '';
    document.getElementById('mermaidOutput').innerHTML = '';
    document.getElementById('errorMsg').classList.remove('visible');
  }

  function openTemplates() {
    document.getElementById('templatesModal').classList.add('active');
  }

  function closeTemplates() {
    document.getElementById('templatesModal').classList.remove('active');
  }

  function loadTemplate(name) {
    if (templates[name]) {
      document.getElementById('codeEditor').value = templates[name];
      closeTemplates();
      renderChart();
    }
  }

  function zoomIn() {
    currentZoom = Math.min(currentZoom + 0.15, 3);
    applyZoom();
  }

  function zoomOut() {
    currentZoom = Math.max(currentZoom - 0.15, 0.3);
    applyZoom();
  }

  function zoomReset() {
    currentZoom = 1;
    applyZoom();
  }

  function applyZoom() {
    const mermaidEl = document.getElementById('mermaidOutput');
    mermaidEl.style.transform = `scale(${currentZoom})`;
  }

  document.getElementById('codeEditor').addEventListener('keydown', function(e) {
    if (e.key === 'Tab') {
      e.preventDefault();
      const start = this.selectionStart;
      const end = this.selectionEnd;
      this.value = this.value.substring(0, start) + '    ' + this.value.substring(end);
      this.selectionStart = this.selectionEnd = start + 4;
    }
  });

  document.getElementById('templatesModal').addEventListener('click', function(e) {
    if (e.target === this) closeTemplates();
  });

  // --- Background Themes ---
  const themeConfigs = {
    default: {
      bg: 'linear-gradient(135deg, #0f0c29, #302b63, #24243e)',
      previewBg: '#1a1a2e',
      text: '#e0e0e0',
      headerBg: 'rgba(0,0,0,0.35)',
      headerBorder: 'rgba(255,255,255,0.1)',
      sidebarBg: 'rgba(0,0,0,0.25)',
      sidebarBorder: 'rgba(255,255,255,0.08)',
      muted: '#b0b0b0',
      dimmed: '#888',
      accent: '#00d2ff',
      accentBg: 'rgba(0,210,255,0.15)',
      accentBorder: 'rgba(0,210,255,0.3)',
      cardBg: 'rgba(0,0,0,0.3)',
      cardBorder: 'rgba(255,255,255,0.08)',
      editorBg: 'rgba(0,0,0,0.4)',
      editorBorder: 'rgba(255,255,255,0.1)',
      badgeBg: 'rgba(123,47,247,0.3)',
      badgeBorder: 'rgba(123,47,247,0.5)',
      badgeText: '#c4a8ff',
      dropdownBg: '#1a1a36',
      dropdownBorder: 'rgba(255,255,255,0.12)',
      modalBg: '#1e1e3a',
      btnBg: 'rgba(255,255,255,0.08)',
      btnBorder: 'rgba(255,255,255,0.1)',
      helpBg: 'rgba(123,47,247,0.2)',
      helpBorder: 'rgba(123,47,247,0.4)',
      helpText: '#c4a8ff',
      exportBg: 'rgba(0,0,0,0.4)'
    },
    midnight: {
      bg: 'linear-gradient(135deg, #0d1117, #161b22, #0d1117)',
      previewBg: '#0d1117',
      text: '#e6edf3',
      headerBg: 'rgba(0,0,0,0.4)',
      headerBorder: 'rgba(255,255,255,0.08)',
      sidebarBg: 'rgba(0,0,0,0.25)',
      sidebarBorder: 'rgba(255,255,255,0.06)',
      muted: '#b0b8c1',
      dimmed: '#7d8590',
      accent: '#58a6ff',
      accentBg: 'rgba(88,166,255,0.15)',
      accentBorder: 'rgba(88,166,255,0.3)',
      cardBg: 'rgba(0,0,0,0.3)',
      cardBorder: 'rgba(255,255,255,0.06)',
      editorBg: 'rgba(0,0,0,0.4)',
      editorBorder: 'rgba(255,255,255,0.08)',
      badgeBg: 'rgba(88,166,255,0.2)',
      badgeBorder: 'rgba(88,166,255,0.4)',
      badgeText: '#79c0ff',
      dropdownBg: '#161b22',
      dropdownBorder: 'rgba(255,255,255,0.1)',
      modalBg: '#161b22',
      btnBg: 'rgba(255,255,255,0.06)',
      btnBorder: 'rgba(255,255,255,0.08)',
      helpBg: 'rgba(88,166,255,0.2)',
      helpBorder: 'rgba(88,166,255,0.4)',
      helpText: '#79c0ff',
      exportBg: 'rgba(0,0,0,0.35)'
    },
    ocean: {
      bg: 'linear-gradient(135deg, #0a1628, #0d2137, #0a1628)',
      previewBg: '#0a1628',
      text: '#d0e8ff',
      headerBg: 'rgba(0,10,30,0.5)',
      headerBorder: 'rgba(100,180,255,0.1)',
      sidebarBg: 'rgba(0,10,30,0.3)',
      sidebarBorder: 'rgba(100,180,255,0.08)',
      muted: '#8cb8d8',
      dimmed: '#5a8aaa',
      accent: '#00b4ff',
      accentBg: 'rgba(0,180,255,0.15)',
      accentBorder: 'rgba(0,180,255,0.3)',
      cardBg: 'rgba(0,10,30,0.4)',
      cardBorder: 'rgba(100,180,255,0.08)',
      editorBg: 'rgba(0,0,0,0.4)',
      editorBorder: 'rgba(100,180,255,0.1)',
      badgeBg: 'rgba(0,180,255,0.2)',
      badgeBorder: 'rgba(0,180,255,0.4)',
      badgeText: '#60d0ff',
      dropdownBg: '#0d2137',
      dropdownBorder: 'rgba(100,180,255,0.12)',
      modalBg: '#0d2137',
      btnBg: 'rgba(100,180,255,0.08)',
      btnBorder: 'rgba(100,180,255,0.1)',
      helpBg: 'rgba(0,180,255,0.2)',
      helpBorder: 'rgba(0,180,255,0.4)',
      helpText: '#60d0ff',
      exportBg: 'rgba(0,0,0,0.35)'
    },
    forest: {
      bg: 'linear-gradient(135deg, #0a1f0d, #143318, #0a1f0d)',
      previewBg: '#0a1f0d',
      text: '#d0f0d0',
      headerBg: 'rgba(0,20,5,0.5)',
      headerBorder: 'rgba(80,200,100,0.1)',
      sidebarBg: 'rgba(0,20,5,0.3)',
      sidebarBorder: 'rgba(80,200,100,0.08)',
      muted: '#8cc88c',
      dimmed: '#5a9a5a',
      accent: '#4caf50',
      accentBg: 'rgba(76,175,80,0.15)',
      accentBorder: 'rgba(76,175,80,0.3)',
      cardBg: 'rgba(0,20,5,0.4)',
      cardBorder: 'rgba(80,200,100,0.08)',
      editorBg: 'rgba(0,0,0,0.4)',
      editorBorder: 'rgba(80,200,100,0.1)',
      badgeBg: 'rgba(76,175,80,0.2)',
      badgeBorder: 'rgba(76,175,80,0.4)',
      badgeText: '#81c784',
      dropdownBg: '#143318',
      dropdownBorder: 'rgba(80,200,100,0.12)',
      modalBg: '#143318',
      btnBg: 'rgba(80,200,100,0.08)',
      btnBorder: 'rgba(80,200,100,0.1)',
      helpBg: 'rgba(76,175,80,0.2)',
      helpBorder: 'rgba(76,175,80,0.4)',
      helpText: '#81c784',
      exportBg: 'rgba(0,0,0,0.35)'
    },
    sunset: {
      bg: 'linear-gradient(135deg, #1a0a0a, #2d1520, #1a0a0a)',
      previewBg: '#1a0a0a',
      text: '#f0d0d0',
      headerBg: 'rgba(30,5,5,0.5)',
      headerBorder: 'rgba(255,120,120,0.1)',
      sidebarBg: 'rgba(30,5,5,0.3)',
      sidebarBorder: 'rgba(255,120,120,0.08)',
      muted: '#d8a0a0',
      dimmed: '#aa7070',
      accent: '#ff6b6b',
      accentBg: 'rgba(255,107,107,0.15)',
      accentBorder: 'rgba(255,107,107,0.3)',
      cardBg: 'rgba(30,5,5,0.4)',
      cardBorder: 'rgba(255,120,120,0.08)',
      editorBg: 'rgba(0,0,0,0.4)',
      editorBorder: 'rgba(255,120,120,0.1)',
      badgeBg: 'rgba(255,107,107,0.2)',
      badgeBorder: 'rgba(255,107,107,0.4)',
      badgeText: '#ff9a9a',
      dropdownBg: '#2d1520',
      dropdownBorder: 'rgba(255,120,120,0.12)',
      modalBg: '#2d1520',
      btnBg: 'rgba(255,120,120,0.08)',
      btnBorder: 'rgba(255,120,120,0.1)',
      helpBg: 'rgba(255,107,107,0.2)',
      helpBorder: 'rgba(255,107,107,0.4)',
      helpText: '#ff9a9a',
      exportBg: 'rgba(0,0,0,0.35)'
    },
    light: {
      bg: 'linear-gradient(135deg, #e8ecf1, #d5dce6, #e8ecf1)',
      previewBg: '#c8cdd5',
      text: '#1a1a2e',
      headerBg: 'rgba(255,255,255,0.6)',
      headerBorder: 'rgba(0,0,0,0.1)',
      sidebarBg: 'rgba(255,255,255,0.4)',
      sidebarBorder: 'rgba(0,0,0,0.08)',
      muted: '#444',
      dimmed: '#777',
      accent: '#1565c0',
      accentBg: 'rgba(21,101,192,0.1)',
      accentBorder: 'rgba(21,101,192,0.3)',
      cardBg: 'rgba(255,255,255,0.5)',
      cardBorder: 'rgba(0,0,0,0.08)',
      editorBg: 'rgba(255,255,255,0.6)',
      editorBorder: 'rgba(0,0,0,0.12)',
      badgeBg: 'rgba(21,101,192,0.12)',
      badgeBorder: 'rgba(21,101,192,0.3)',
      badgeText: '#1565c0',
      dropdownBg: '#ffffff',
      dropdownBorder: 'rgba(0,0,0,0.12)',
      modalBg: '#ffffff',
      btnBg: 'rgba(0,0,0,0.06)',
      btnBorder: 'rgba(0,0,0,0.1)',
      helpBg: 'rgba(21,101,192,0.1)',
      helpBorder: 'rgba(21,101,192,0.3)',
      helpText: '#1565c0',
      exportBg: 'rgba(255,255,255,0.6)'
    },
    amber: {
      bg: 'linear-gradient(135deg, #1a1508, #2a2210, #1a1508)',
      previewBg: '#1a1508',
      text: '#f0e8d0',
      headerBg: 'rgba(30,25,5,0.5)',
      headerBorder: 'rgba(255,200,50,0.1)',
      sidebarBg: 'rgba(30,25,5,0.3)',
      sidebarBorder: 'rgba(255,200,50,0.08)',
      muted: '#d0c8a0',
      dimmed: '#a09870',
      accent: '#ffc107',
      accentBg: 'rgba(255,193,7,0.15)',
      accentBorder: 'rgba(255,193,7,0.3)',
      cardBg: 'rgba(30,25,5,0.4)',
      cardBorder: 'rgba(255,200,50,0.08)',
      editorBg: 'rgba(0,0,0,0.4)',
      editorBorder: 'rgba(255,200,50,0.1)',
      badgeBg: 'rgba(255,193,7,0.2)',
      badgeBorder: 'rgba(255,193,7,0.4)',
      badgeText: '#ffd54f',
      dropdownBg: '#2a2210',
      dropdownBorder: 'rgba(255,200,50,0.12)',
      modalBg: '#2a2210',
      btnBg: 'rgba(255,200,50,0.08)',
      btnBorder: 'rgba(255,200,50,0.1)',
      helpBg: 'rgba(255,193,7,0.2)',
      helpBorder: 'rgba(255,193,7,0.4)',
      helpText: '#ffd54f',
      exportBg: 'rgba(0,0,0,0.35)'
    },
    solid_black: {
      bg: '#0a0a0a',
      previewBg: '#000',
      text: '#e0e0e0',
      headerBg: 'rgba(0,0,0,0.5)',
      headerBorder: 'rgba(255,255,255,0.08)',
      sidebarBg: 'rgba(0,0,0,0.3)',
      sidebarBorder: 'rgba(255,255,255,0.06)',
      muted: '#aaa',
      dimmed: '#666',
      accent: '#00d2ff',
      accentBg: 'rgba(0,210,255,0.12)',
      accentBorder: 'rgba(0,210,255,0.25)',
      cardBg: 'rgba(255,255,255,0.04)',
      cardBorder: 'rgba(255,255,255,0.06)',
      editorBg: 'rgba(255,255,255,0.05)',
      editorBorder: 'rgba(255,255,255,0.08)',
      badgeBg: 'rgba(0,210,255,0.15)',
      badgeBorder: 'rgba(0,210,255,0.3)',
      badgeText: '#00d2ff',
      dropdownBg: '#111',
      dropdownBorder: 'rgba(255,255,255,0.1)',
      modalBg: '#111',
      btnBg: 'rgba(255,255,255,0.06)',
      btnBorder: 'rgba(255,255,255,0.08)',
      helpBg: 'rgba(0,210,255,0.15)',
      helpBorder: 'rgba(0,210,255,0.3)',
      helpText: '#00d2ff',
      exportBg: 'rgba(255,255,255,0.05)'
    },
    solid_white: {
      bg: '#f5f5f5',
      previewBg: '#e0e0e0',
      text: '#1a1a2e',
      headerBg: 'rgba(255,255,255,0.7)',
      headerBorder: 'rgba(0,0,0,0.1)',
      sidebarBg: 'rgba(255,255,255,0.5)',
      sidebarBorder: 'rgba(0,0,0,0.08)',
      muted: '#555',
      dimmed: '#888',
      accent: '#1565c0',
      accentBg: 'rgba(21,101,192,0.1)',
      accentBorder: 'rgba(21,101,192,0.25)',
      cardBg: 'rgba(255,255,255,0.6)',
      cardBorder: 'rgba(0,0,0,0.08)',
      editorBg: 'rgba(255,255,255,0.7)',
      editorBorder: 'rgba(0,0,0,0.1)',
      badgeBg: 'rgba(21,101,192,0.12)',
      badgeBorder: 'rgba(21,101,192,0.3)',
      badgeText: '#1565c0',
      dropdownBg: '#ffffff',
      dropdownBorder: 'rgba(0,0,0,0.12)',
      modalBg: '#ffffff',
      btnBg: 'rgba(0,0,0,0.05)',
      btnBorder: 'rgba(0,0,0,0.1)',
      helpBg: 'rgba(21,101,192,0.1)',
      helpBorder: 'rgba(21,101,192,0.3)',
      helpText: '#1565c0',
      exportBg: 'rgba(255,255,255,0.7)'
    }
  };

  function setBackground(name, el) {
    currentTheme = name;
    const t = themeConfigs[name] || themeConfigs.default;
    const r = document.documentElement;

    r.style.setProperty('--app-bg', t.bg);
    document.body.style.background = t.bg;

    document.getElementById('preview').style.background = t.previewBg;

    const header = document.querySelector('header');
    header.style.background = t.headerBg;
    header.style.borderBottomColor = t.headerBorder;

    const sidebar = document.querySelector('.sidebar');
    sidebar.style.background = t.sidebarBg;
    sidebar.style.borderRightColor = t.sidebarBorder;

    document.querySelector('.sidebar-header').style.borderBottomColor = t.sidebarBorder;
    document.querySelector('.preview-header').style.borderBottomColor = t.sidebarBorder;

    document.querySelectorAll('.sidebar-header h2, .preview-header h2').forEach(h => h.style.color = t.muted);

    document.querySelectorAll('.editor-wrapper label').forEach(l => l.style.color = t.dimmed);

    const editor = document.getElementById('codeEditor');
    editor.style.background = t.editorBg;
    editor.style.borderColor = t.editorBorder;

    document.querySelector('.actions').style.gap = '10px';

    document.querySelectorAll('.btn-primary').forEach(b => {
      b.style.background = `linear-gradient(135deg, ${t.accent}, #7b2ff7)`;
    });

    document.querySelectorAll('.btn-secondary').forEach(b => {
      b.style.background = t.btnBg;
      b.style.borderColor = t.btnBorder;
      b.style.color = t.muted;
    });

    document.querySelectorAll('.btn-success').forEach(b => {
      b.style.background = `linear-gradient(135deg, #00c853, #00bfa5)`;
    });

    document.querySelectorAll('.zoom-btn').forEach(b => {
      b.style.background = t.btnBg;
      b.style.borderColor = t.btnBorder;
      b.style.color = t.muted;
    });

    document.querySelectorAll('.templates-btn').forEach(b => {
      b.style.background = t.accentBg;
      b.style.borderColor = t.accentBorder;
      b.style.color = t.accent;
    });

    document.querySelectorAll('.help-btn').forEach(b => {
      b.style.background = t.helpBg;
      b.style.borderColor = t.helpBorder;
      b.style.color = t.helpText;
    });

    document.querySelectorAll('.badge').forEach(b => {
      b.style.background = t.badgeBg;
      b.style.borderColor = t.badgeBorder;
      b.style.color = t.badgeText;
    });

    document.querySelectorAll('.modal').forEach(m => {
      m.style.background = t.modalBg;
      m.style.borderColor = t.cardBorder;
    });

    document.querySelectorAll('.modal h3').forEach(h => h.style.color = t.text);

    document.querySelectorAll('.dropdown-menu').forEach(d => {
      d.style.background = t.dropdownBg;
      d.style.borderColor = t.dropdownBorder;
    });

    document.querySelectorAll('.dropdown-toggle').forEach(d => {
      d.style.background = t.btnBg;
      d.style.borderColor = t.btnBorder;
      d.style.color = t.muted;
    });

    document.querySelectorAll('.template-card').forEach(c => {
      c.style.background = t.cardBg;
      c.style.borderColor = t.cardBorder;
    });

    document.querySelectorAll('.template-card h4').forEach(h => h.style.color = t.text);
    document.querySelectorAll('.template-card p').forEach(p => p.style.color = t.dimmed);

    document.querySelectorAll('.help-table th').forEach(th => th.style.color = t.dimmed);
    document.querySelectorAll('.help-table td').forEach(td => td.style.color = t.muted);
    document.querySelectorAll('.help-table td code').forEach(c => {
      c.style.color = t.accent;
    });
    document.querySelectorAll('.help-section h4').forEach(h => h.style.color = t.accent);

    document.querySelectorAll('.modal-overlay').forEach(o => {
      o.style.background = 'rgba(0,0,0,0.7)';
    });

    document.querySelectorAll('.error-msg').forEach(e => {
      e.style.background = 'rgba(255,60,60,0.15)';
      e.style.borderColor = 'rgba(255,60,60,0.3)';
      e.style.color = '#ff6b6b';
    });

    if (currentFontColor === 'auto') {
      applyFontColors(t.text, t.muted, t.dimmed, t.accent);
      reinitMermaid(t.text);
    } else {
      applyFontColors(currentFontColor, currentFontColor, currentFontColor, currentFontColor);
      reinitMermaid(currentFontColor);
    }

    setActiveItem('bgDropdown', el);
    closeAllDropdowns();
  }

  // --- Font Themes ---
  let currentFontColor = 'auto';

  function setFontColor(color, el) {
    currentFontColor = color;
    if (color === 'auto') {
      const t = themeConfigs[currentTheme] || themeConfigs.default;
      applyFontColors(t.text, t.muted, t.dimmed, t.accent);
      reinitMermaid(t.text);
    } else {
      applyFontColors(color, color, color, color);
      reinitMermaid(color);
    }
    setActiveItemById('fontColorGroup', el);
    closeAllDropdowns();
  }

  function reinitMermaid(textColor) {
    mermaid.initialize({
      startOnLoad: false,
      theme: 'dark',
      themeVariables: {
        primaryColor: '#7b2ff7',
        primaryTextColor: textColor,
        primaryBorderColor: '#00d2ff',
        lineColor: '#00d2ff',
        secondaryColor: '#1e1e3a',
        tertiaryColor: '#0f0c29',
        fontFamily: 'Segoe UI, sans-serif',
        fontSize: '14px'
      },
      flowchart: { htmlLabels: true, curve: 'basis', padding: 20, nodeSpacing: 50, rankSpacing: 60 }
    });
    renderChart();
  }

  function applyFontColors(text, muted, dimmed, accent) {
    document.body.style.color = text;
    document.querySelectorAll('.sidebar-header h2, .preview-header h2').forEach(h => h.style.color = muted);
    document.querySelectorAll('.editor-wrapper label').forEach(l => l.style.color = dimmed);
    document.querySelectorAll('.dropdown-toggle').forEach(d => d.style.color = muted);
    document.querySelectorAll('.zoom-btn').forEach(b => b.style.color = muted);
    document.querySelectorAll('.modal h3').forEach(h => h.style.color = text);
    document.querySelectorAll('.template-card h4').forEach(h => h.style.color = text);
    document.querySelectorAll('.template-card p').forEach(p => p.style.color = dimmed);
    document.querySelectorAll('.help-table td').forEach(td => td.style.color = muted);
    document.querySelectorAll('.help-table th').forEach(th => th.style.color = dimmed);
    document.querySelectorAll('.help-section h4').forEach(h => h.style.color = accent);
    document.querySelectorAll('.help-table td code').forEach(c => c.style.color = accent);
    document.querySelectorAll('.badge').forEach(b => {
      b.style.color = accent;
    });
    document.querySelectorAll('.templates-btn').forEach(b => b.style.color = accent);
    document.querySelectorAll('.help-btn').forEach(b => b.style.color = accent);
    document.getElementById('codeEditor').style.color = text;
  }

  function setActiveItemById(groupId, el) {
    if (!el) return;
    const parent = el.parentElement;
    if (parent) {
      parent.querySelectorAll('.dropdown-item').forEach(i => i.classList.remove('active'));
      el.classList.add('active');
    }
  }

  let currentTheme = 'default';

  function setFont(family, label, el) {
    document.body.style.fontFamily = family;
    document.getElementById('codeEditor').style.fontFamily = family.includes('Segoe') ? "'Fira Code', 'Cascadia Code', 'Consolas', monospace" : family;
    setActiveItem('fontDropdown', el);
    closeAllDropdowns();
  }

  function setFontSize(size, el) {
    document.documentElement.style.setProperty('--app-font-size', size);
    const previewTextColor = currentFontColor === 'auto'
      ? (themeConfigs[currentTheme] || themeConfigs.default).text
      : currentFontColor;
    mermaid.initialize({
      startOnLoad: false,
      theme: 'dark',
      themeVariables: {
        primaryColor: '#7b2ff7',
        primaryTextColor: previewTextColor,
        primaryBorderColor: '#00d2ff',
        lineColor: '#00d2ff',
        secondaryColor: '#1e1e3a',
        tertiaryColor: '#0f0c29',
        fontFamily: 'Segoe UI, sans-serif',
        fontSize: size
      },
      flowchart: { htmlLabels: true, curve: 'basis', padding: 20, nodeSpacing: 50, rankSpacing: 60 }
    });
    setActiveItem('fontDropdown', el);
    closeAllDropdowns();
    renderChart();
  }

  // --- Dropdowns ---
  function toggleDropdown(id) {
    const menu = document.getElementById(id);
    const wasOpen = menu.classList.contains('show');
    closeAllDropdowns();
    if (!wasOpen) menu.classList.add('show');
  }

  function closeAllDropdowns() {
    document.querySelectorAll('.dropdown-menu').forEach(m => m.classList.remove('show'));
  }

  function setActiveItem(menuId, el) {
    const menu = document.getElementById(menuId);
    menu.querySelectorAll('.dropdown-item').forEach(i => i.classList.remove('active'));
    el.classList.add('active');
  }

  document.addEventListener('click', function(e) {
    if (!e.target.closest('.dropdown')) closeAllDropdowns();
  });

  // --- Help ---
  function openHelp() {
    document.getElementById('helpModal').classList.add('active');
  }

  function closeHelp() {
    document.getElementById('helpModal').classList.remove('active');
  }

  document.getElementById('helpModal').addEventListener('click', function(e) {
    if (e.target === this) closeHelp();
  });

  // --- Keyboard shortcuts ---
  document.addEventListener('keydown', function(e) {
    if (e.key === 'Escape') {
      closeAllDropdowns();
      closeTemplates();
      closeHelp();
    }
    if (e.ctrlKey && e.key === 'Enter') {
      e.preventDefault();
      renderChart();
    }
  });

  renderChart();
