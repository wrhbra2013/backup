/*
 * instagram-feed-browser.js
 * Cole inteiro no Console do navegador (F12) na página do perfil do Instagram.
 * Percorre todas as postagens do perfil, agrupa por mês e baixa o JSON automaticamente.
 *
 * Uso:
 *   1. Logue no Instagram e abra https://www.instagram.com/SEU_USUARIO/
 *   2. F12 -> Console -> cole este arquivo inteiro -> Enter
 *   3. Aguarde (pode levar vários minutos). Ao final, o arquivo
 *      instagram-<usuario>-resumo-mensal.json é baixado automaticamente.
 *
 * Ajuste USERNAME abaixo se não estiver na página do perfil.
 */
(async () => {
  const USERNAME = "grupoamoranimal";
  const DELAY_MS = 1500; // pausa entre requisições (evita bloqueio)
  const PAGE_SIZE = 12;  // posts por página retornados pela API
  const MAX_PAGES = 400; // limite de segurança
  const H = { "X-IG-App-ID": "936619743392459" };

  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  const pad2 = (n) => String(n).padStart(2, "0");

  console.log("[insta] Buscando ID de @" + USERNAME + "...");
  const profRes = await fetch(
    "/api/v1/users/web_profile_info/?username=" + USERNAME,
    { headers: H }
  );
  const prof = await profRes.json();
  const user = prof.data && prof.data.user;
  if (!user || !user.id) {
    console.error("[insta] Nao conseguiu resolver o perfil. Esta logado?");
    return;
  }
  const id = user.id;

  console.log("[insta] ID:", id, "| posts totais:", user.edge_owner_to_timeline_media.count);

  let maxid = null;
  let all = [];
  let pages = 0;

  do {
    const url = "/api/v1/feed/user/" + id + "/?count=" + PAGE_SIZE + (maxid ? "&max_id=" + maxid : "");
    let f;
    try {
      const r = await fetch(url, { headers: H });
      f = await r.json();
    } catch (e) {
      console.warn("[insta] erro na pagina " + pages + ", tentando de novo...", e.message);
      await sleep(3000);
      continue;
    }
    if (!f.items || !f.items.length) break;

    all = all.concat(f.items);
    maxid = f.next_max_id || null;
    pages++;

    if (pages % 5 === 0) console.log("[insta] coletados " + all.length + " posts (" + pages + " paginas)...");
    if (pages % 30 === 0) console.log("[insta] ainda rodando... " + all.length + " posts coletados");

    await sleep(DELAY_MS);
  } while (maxid && pages < MAX_PAGES);

  console.log("[insta] TOTAL de posts coletados:", all.length);

  // ---- Agrupa por mes ----
  const porMes = {};
  all.forEach((i) => {
    const d = new Date(i.taken_at * 1000);
    const mes = d.getFullYear() + "-" + pad2(d.getMonth() + 1);
    if (!porMes[mes]) {
      porMes[mes] = { posts: 0, likes: 0, comentarios: 0, imagens: 0, videos: 0, carrosseis: 0 };
    }
    porMes[mes].posts++;
    porMes[mes].likes += i.like_count || 0;
    porMes[mes].comentarios += i.comment_count || 0;
    if (i.media_type === 2) porMes[mes].videos++;
    else if (i.media_type === 8) porMes[mes].carrosseis++;
    else porMes[mes].imagens++;
  });

  const meses = Object.keys(porMes).sort().reverse();
  const resumoPorMes = meses.map((m) => {
    const v = porMes[m];
    return {
      mes: m,
      quantidade_posts: v.posts,
      total_likes: v.likes,
      total_comentarios: v.comentarios,
      media_likes_por_post: +(v.likes / v.posts).toFixed(1),
      media_comentarios_por_post: +(v.comentarios / v.posts).toFixed(1),
      imagens: v.imagens,
      videos: v.videos,
      carrosseis: v.carrosseis,
    };
  });

  const totalLikes = all.reduce((s, i) => s + (i.like_count || 0), 0);
  const totalComments = all.reduce((s, i) => s + (i.comment_count || 0), 0);

  const summary = {
    perfil: {
      username: user.username,
      nome: user.full_name,
      bio: user.biography,
      seguidores: user.edge_followed_by.count,
      seguindo: user.edge_follow.count,
      total_posts: user.edge_owner_to_timeline_media.count,
      eh_verificado: user.is_verified,
      url_perfil: user.profile_pic_url_hd,
      url: "https://www.instagram.com/" + user.username + "/",
    },
    estatisticas: {
      posts_baixados: all.length,
      total_likes: totalLikes,
      total_comentarios: totalComments,
      media_likes_por_post: all.length ? +(totalLikes / all.length).toFixed(1) : 0,
      media_comentarios_por_post: all.length ? +(totalComments / all.length).toFixed(1) : 0,
    },
    resumo_por_mes: resumoPorMes,
    posts: all.map((i) => ({
      code: i.code,
      data: new Date(i.taken_at * 1000).toISOString(),
      tipo: i.media_type === 2 ? "VIDEO" : i.media_type === 8 ? "CAROUSEL" : "IMAGE",
      likes: i.like_count || 0,
      comentarios: i.comment_count || 0,
      legenda: (i.caption && i.caption.text) || null,
      url: "https://www.instagram.com/p/" + i.code + "/",
    })),
    buscado_em: new Date().toISOString(),
  };

  // ---- Baixa o JSON ----
  const blob = new Blob([JSON.stringify(summary, null, 2)], { type: "application/json" });
  const a = document.createElement("a");
  a.href = URL.createObjectURL(blob);
  a.download = "instagram-" + USERNAME + "-resumo-mensal.json";
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);

  // ---- Imprime resumo no console ----
  console.log("===== RESUMO POR MES =====");
  console.log("MES        POSTS  LIKES   COM  MED-LIKE");
  resumoPorMes.forEach((m) => {
    console.log(
      m.mes.padEnd(10) +
        String(m.quantidade_posts).padStart(5) +
        String(m.total_likes).padStart(8) +
        String(m.total_comentarios).padStart(6) +
        String(m.media_likes_por_post).padStart(9)
    );
  });
  console.log("[insta] Arquivo baixado: instagram-" + USERNAME + "-resumo-mensal.json");
  console.log("[insta] Posts baixados:", all.length, "de", user.edge_owner_to_timeline_media.count);
})();
