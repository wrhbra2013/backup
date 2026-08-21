/**
 * load_linha_do_tempo.js — Renderiza carrossel horizontal da linha do tempo
 * combinando posts do Instagram + eventos da API.
 *
 * Depende de: api.js (apiFetch, window.API_BASE)
 * Nao modifica nenhum script existente.
 *
 * Uso no HTML:
 *   <script src="static/js/load_linha_do_tempo.js"></script>
 */
(function() {
  'use strict';

  var BASE = window.API_BASE || 'https://api.projetosdinamicos.com.br/amoranimal';

  function fmtDate(d) {
    if (!d) return '';
    if (d.match(/^\d{2}\/\d{2}\/\d{4}$/)) return d;
    var partes = d.split('T')[0].split('-');
    if (partes.length === 3 && partes[0].length === 4) {
      var meses = ['Jan','Fev','Mar','Abr','Mai','Jun','Jul','Ago','Set','Out','Nov','Dez'];
      var mi = parseInt(partes[1], 10) - 1;
      return partes[2] + ' ' + (meses[mi] || partes[1]) + ' ' + partes[0];
    }
    return d;
  }

  function esc(s) {
    if (!s) return '';
    var e = document.createElement('div');
    e.appendChild(document.createTextNode(s));
    return e.innerHTML;
  }

  function criarCard(item) {
    var card = document.createElement('div');
    card.className = 'lt-card';

    var isIG = item.tipo === 'instagram';
    var badgeCor = isIG ? 'background:#c13584;color:#fff;' : 'background:var(--brand-teal);color:#fff;';
    var badgeTxt = isIG ? '<i class="bi bi-instagram"></i> Instagram' : '<i class="bi bi-calendar-event"></i> Evento';
    var badgeClass = isIG ? 'lt-badge-ig' : 'lt-badge-ev';

    var fotoHtml = '';
    if (item.foto_url) {
      fotoHtml = '<img src="' + esc(item.foto_url) + '" alt="' + esc(item.titulo) + '" loading="lazy">';
    } else {
      var icone = isIG ? 'bi-instagram' : 'bi-calendar-event';
      fotoHtml = '<div class="lt-card-placeholder"><i class="bi ' + icone + '"></i></div>';
    }

    var linkHtml = '';
    if (item.link) {
      linkHtml = '<a href="' + esc(item.link) + '" target="_blank" rel="noopener" class="lt-card-link">' +
        '<span class="lt-card-link-text">' + (isIG ? 'Ver no Instagram' : 'Ver evento') + ' <i class="bi bi-box-arrow-up-right"></i></span></a>';
    }

    var likesHtml = '';
    if (isIG && item.likes) {
      likesHtml = '<span class="lt-likes"><i class="bi bi-heart-fill"></i> ' + item.likes + '</span>';
    }

    card.innerHTML =
      '<div class="lt-card-foto">' + fotoHtml +
        '<span class="lt-badge ' + badgeClass + '">' + badgeTxt + '</span>' +
        '<span class="lt-card-data">' + fmtDate(item.data) + '</span>' +
      '</div>' +
      '<div class="lt-card-info">' +
        '<p class="lt-card-titulo">' + esc(item.titulo.substring(0, 80)) + '</p>' +
        '<div class="lt-card-meta">' + likesHtml +
          (item.local ? '<span><i class="bi bi-geo-alt"></i> ' + esc(item.local) + '</span>' : '') +
          (item.categoria && isIG ? '<span class="lt-cat-' + item.categoria + '">' + esc(item.categoria) + '</span>' : '') +
        '</div>' +
        linkHtml +
      '</div>';

    return card;
  }

  function renderizar(container, items) {
    container.innerHTML = '';
    if (!items.length) {
      container.innerHTML = '<p class="text-center text-muted" style="width:100%;padding:2rem;">Nenhum item na linha do tempo.</p>';
      return;
    }

    var wrapper = document.createElement('div');
    wrapper.className = 'lt-carousel-wrapper';

    var carousel = document.createElement('div');
    carousel.className = 'lt-carousel';

    items.forEach(function(item) {
      carousel.appendChild(criarCard(item));
    });

    wrapper.appendChild(carousel);

    // Botoes de navegacao
    var btnPrev = document.createElement('button');
    btnPrev.className = 'lt-nav lt-nav-prev';
    btnPrev.innerHTML = '<i class="bi bi-chevron-left"></i>';
    btnPrev.onclick = function() {
      carousel.scrollBy({ left: -320, behavior: 'smooth' });
    };

    var btnNext = document.createElement('button');
    btnNext.className = 'lt-nav lt-nav-next';
    btnNext.innerHTML = '<i class="bi bi-chevron-right"></i>';
    btnNext.onclick = function() {
      carousel.scrollBy({ left: 320, behavior: 'smooth' });
    };

    wrapper.appendChild(btnPrev);
    wrapper.appendChild(btnNext);
    container.appendChild(wrapper);
  }

  document.addEventListener('DOMContentLoaded', function() {
    var container = document.getElementById('linhaDoTempoGrid');
    if (!container) return;

    // Buscar linha do tempo da API + eventos
    Promise.all([
      apiFetch('/linha_do_tempo')
        .then(function(r) { return r.ok ? r.json() : []; })
        .catch(function() { return []; }),
      apiFetch('/eventos')
        .then(function(r) { return r.ok ? r.json() : []; })
        .catch(function() { return []; })
    ]).then(function(results) {
      var itemsLT = Array.isArray(results[0]) ? results[0] : [];
      var eventos = Array.isArray(results[1]) ? results[1] : [];

      // Se endpoint /linha_do_tempo ainda nao existe, usar apenas eventos
      var todos = itemsLT.length > 0 ? itemsLT : [];

      // Adicionar eventos que ainda nao estao na linha do tempo
      var refsExistentes = new Set(todos.map(function(t) { return t.ref || t.id; }));
      eventos.forEach(function(ev) {
        var ref = 'ev_' + ev.id;
        if (!refsExistentes.has(ref)) {
          todos.push({
            ref: ref,
            tipo: 'evento',
            titulo: ev.titulo || 'Evento',
            descricao: ev.descricao || '',
            foto_url: (function() {
              var f = ev.fotos || ev.arquivo;
              if (!f) return '';
              if (f.startsWith('http') || f.startsWith('data:')) return f;
              return BASE + '/uploads/eventos/' + f;
            })(),
            data: (ev.data_evento || ev.created_at || '').split('T')[0],
            local: ev.local || ev.endereco || '',
            link: '',
            likes: 0,
            origem: 'api'
          });
        }
      });

      // Ordenar por data (mais recente primeiro)
      todos.sort(function(a, b) {
        return (b.data || '').localeCompare(a.data || '');
      });

      renderizar(container, todos);
    });
  });
})();
