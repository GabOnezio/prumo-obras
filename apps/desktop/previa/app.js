'use strict';

// Prévia do Prumo. Esta camada só desenha: todo número, data e regra vem do
// Rust (comando `painel` e as ações), nunca é calculado aqui.

const invocar = (comando, argumentos) => window.__TAURI__.core.invoke(comando, argumentos);

const conteudo = document.getElementById('conteudo');
const aviso = document.getElementById('aviso');
const usuario = document.getElementById('usuario');
const dialogo = document.getElementById('confirmar');

let painel = null;
let eventoSelecionado = null;
let temporizadorDoAviso = null;
const fragmentos = new Map();

const esc = (texto) =>
  String(texto).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);

// ---------------------------------------------------------------- componentes

const RELOGIO =
  '<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/></svg>';
const ESTRELA =
  '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 3l1.8 5.2L19 10l-5.2 1.8L12 17l-1.8-5.2L5 10l5.2-1.8z"/></svg>';

const seloPrevisao = (texto = 'Previsão') => `<span class="selo selo-previsao">${RELOGIO}${esc(texto)}</span>`;

function pilula(situacao) {
  const classe = { concluido: 'pilula-ok', em_andamento: 'pilula-atencao' }[situacao.codigo] || 'pilula-neutra';
  return `<span class="pilula ${classe}">${esc(situacao.rotulo)}</span>`;
}

const indicador = (rotulo, valor, previsao = false) => `
  <div class="indicador${previsao ? ' e-previsao' : ''}">
    <div class="indicador-rotulo">${previsao ? RELOGIO + ' Previsão · ' : ''}${esc(rotulo)}</div>
    <div class="indicador-valor">${esc(valor)}</div>
  </div>`;

const migalha = () =>
  `<div class="migalha">Contrato ${esc(painel.contrato.numero)} · ${esc(painel.contrato.obra)} · ${esc(painel.contrato.revisao)} · ${esc(painel.contrato.forma_de_medir)} · ${esc(painel.contrato.cronograma)}</div>`;

/** Lugar onde a IA local vai aparecer. Nesta prévia nenhum modelo roda. */
const iaDesligada = (oQueFara) => `
  <div class="caixa caixa-ia">
    <div class="caixa-titulo">${ESTRELA} Sugestão da IA local <span class="pilula pilula-neutra">desligada nesta prévia</span></div>
    <div>${esc(oQueFara)}</div>
  </div>`;

function tabelaDeServicos(servicos, rotuloDoTotal, total) {
  const linhas = servicos
    .map(
      (s) => `<tr>
        <td>${esc(s.item)}</td><td>${esc(s.descricao)}</td>
        <td class="num">${esc(s.quantidade)}</td><td class="num">${esc(s.preco_unitario)}</td><td class="num">${esc(s.valor)}</td>
      </tr>`,
    )
    .join('');
  return `<div class="rolagem"><table>
    <thead><tr><th>Item</th><th>Serviço da planilha</th><th class="num">Qtd. na frente</th><th class="num">Preço unit.</th><th class="num">Valor</th></tr></thead>
    <tbody>${linhas}</tbody>
    <tfoot><tr><td colspan="4" class="num">${esc(rotuloDoTotal)}</td><td class="num">${esc(total)}</td></tr></tfoot>
  </table></div>`;
}

// ---------------------------------------------------------------------- telas

function telaInicio() {
  return `<div class="tela">
    <div class="cabecalho"><img class="marca-sobre" src="marca-preta.svg" alt="Marca do Prumo"><div class="cabecalho-texto">
      <div class="migalha">Prumo · Gestão de Obras Públicas</div>
      <h1>Sobre esta prévia</h1>
      <div class="subtitulo">Esta janela mostra como o Prumo está ficando. Os dados são fictícios (município de Exemplo, Contrato ${esc(painel.contrato.numero)}) e nada é gravado: ao fechar, tudo volta ao início.</div>
    </div></div>

    <div class="indicadores">
      ${indicador('Total da planilha', 'R$ ' + painel.total_da_planilha)}
      ${indicador('Físico verificado', painel.fisico_verificado)}
      ${indicador('Término contratual', painel.contrato.termino_contratual)}
      ${indicador('término da obra', painel.previsao.termino_previsto, true)}
    </div>

    <div class="duas-colunas">
      <div class="coluna-principal">
        <section class="cartao">
          <div class="cartao-titulo"><h2>Experimente</h2></div>
          <div class="cartao-corpo">
            <ol class="lista">
              <li>Abra <a href="#/medicao">Medição por eventos</a>. Aprovar está bloqueado: o Boletim de Execução nº 7 marca a Alvenaria como em andamento.</li>
              <li>Vá ao <a href="#/boletim">Boletim de Execução</a> nº 8, marque a Alvenaria como concluída e emita o boletim.</li>
              <li>Volte à medição: agora o evento está conferido e dá para aprovar.</li>
              <li>Abra a <a href="#/previsao">Previsão</a> e veja término e pagamentos recalculados.</li>
            </ol>
            <p>Outro caminho: reinicie, informe 71% de avanço no boletim e emita. O pagamento da Alvenaria passa de fevereiro para março, porque o evento deixa de terminar dentro da medição de dezembro.</p>
          </div>
        </section>

        <section class="cartao">
          <div class="cartao-titulo"><h2>O que já é cálculo de verdade</h2><span class="nota">código Rust com testes</span></div>
          <div class="cartao-corpo">
            <ul class="lista">
              <li>Valor de cada evento: quantidade na frente × preço unitário, serviço a serviço, com o arredondamento do contrato.</li>
              <li>Regra do Boletim de Execução: evento só é aprovado na medição se o último boletim emitido o marca concluído.</li>
              <li>Glosa do evento inteiro, e boletim e medição imutáveis depois de emitidos ou aprovados.</li>
              <li>Previsão de término pelo ritmo verificado e pelo fator de ritmo da obra, em dias úteis do calendário.</li>
              <li>Previsão de pagamento e desembolso por mês, pelos prazos de processo configurados e com retenção.</li>
            </ul>
          </div>
        </section>
      </div>

      <div class="coluna-lateral">
        <div class="caixa caixa-desenho">
          <div class="caixa-titulo">Ainda é só desenho</div>
          <div>As telas marcadas com "desenho" no menu (painel, medição por quantidade, console de IA) mostram números de exemplo, fixos.</div>
        </div>
        <div class="caixa caixa-desenho">
          <div class="caixa-titulo">Ainda não existe</div>
          <ul class="lista">
            <li>Banco de dados, login, perfis e designação de fiscal</li>
            <li>Assinatura e trilha de auditoria</li>
            <li>Leitura de planilha, cronograma e projeto do órgão</li>
            <li>Relatórios em PDF e planilha</li>
            <li>App de celular: é só nele que existe o diário de obras da empresa</li>
            <li>IA local</li>
          </ul>
        </div>
      </div>
    </div>
  </div>`;
}

function telaEventos() {
  const cartoes = painel.eventos
    .map(
      (e) => `<section class="cartao">
        <div class="cartao-titulo">
          <h2>${esc(e.nome)}</h2>
          ${pilula(e.situacao)}
          <span class="nota">Linha de base ${esc(e.linha_de_base)}</span>
        </div>
        ${tabelaDeServicos(e.servicos, 'Valor do evento', e.valor)}
      </section>`,
    )
    .join('');
  return `<div class="tela">
    <div class="cabecalho"><div class="cabecalho-texto">
      ${migalha()}
      <h1>Planilha e eventos</h1>
      <div class="subtitulo">Cada serviço da planilha do órgão cai em um evento (agrupador × frente). O valor do evento é calculado; ninguém digita.</div>
    </div></div>
    <div class="indicadores">
      ${indicador('Total da planilha', 'R$ ' + painel.total_da_planilha)}
      ${indicador('Eventos', String(painel.eventos.length))}
      ${indicador(`Físico verificado (Boletim nº ${painel.boletim_vigente.numero})`, painel.fisico_verificado)}
    </div>
    ${cartoes}
  </div>`;
}

function telaBoletim() {
  const r = painel.rascunho;
  const linhas = r.linhas
    .map((l) => {
      if (!l.editavel) {
        return `<tr>
          <td class="sem-quebra">${esc(l.nome)}</td><td class="sem-quebra">${esc(l.linha_de_base)}</td>
          <td>${pilula(l.situacao)}</td>
          <td class="sem-dado sem-quebra">${r.emitido ? '' : 'igual ao Boletim nº 7'}</td>
        </tr>`;
      }
      const emAndamento = r.situacao === 'em_andamento';
      return `<tr class="selecionada">
        <td class="sem-quebra"><strong>${esc(l.nome)}</strong></td><td class="sem-quebra">${esc(l.linha_de_base)}</td>
        <td><select data-campo="situacao" aria-label="Situação de ${esc(l.nome)}">
          <option value="em_andamento"${emAndamento ? ' selected' : ''}>Em andamento</option>
          <option value="concluido"${emAndamento ? '' : ' selected'}>Concluído</option>
        </select></td>
        <td>${
          emAndamento
            ? `<input class="avanco" type="text" inputmode="numeric" data-campo="avanco" value="${esc(r.avanco)}" aria-label="Avanço verificado de ${esc(l.nome)}, em %"> %`
            : `na vistoria de ${esc(r.vistoria_em)}`
        }</td>
      </tr>`;
    })
    .join('');

  return `<div class="tela">
    <div class="cabecalho">
      <div class="cabecalho-texto">
        ${migalha()}
        <h1>Boletim de Execução nº ${r.numero} <span class="pilula ${r.emitido ? 'pilula-ok' : 'pilula-neutra'}">${r.emitido ? 'Emitido' : 'Rascunho'}</span></h1>
        <div class="subtitulo">Período ${esc(r.periodo)} · fiscal designada: Maria Souza · vistoria em ${esc(r.vistoria_em)}</div>
      </div>
      <div class="cabecalho-acoes">
        <button type="button" class="btn btn-primario" data-acao="emitir"${r.emitido ? ' disabled' : ''}>Emitir e assinar</button>
        ${r.emitido ? '<div class="nota">Boletim emitido é imutável. Correção só por boletim retificador.</div>' : ''}
      </div>
    </div>

    <div class="indicadores">
      ${indicador('Eventos do contrato', String(r.linhas.length))}
      ${indicador('Concluídos neste boletim', String(r.concluidos))}
      ${indicador('Em andamento', String(r.em_andamento))}
      ${indicador(`Físico verificado (Boletim nº ${painel.boletim_vigente.numero}, emitido)`, painel.fisico_verificado)}
    </div>

    <div class="duas-colunas">
      <div class="coluna-principal">
        <section class="cartao">
          <div class="cartao-titulo"><h2>Situação dos eventos</h2><span class="nota">O que você conferiu no local</span></div>
          <div class="rolagem"><table>
            <thead><tr><th>Evento (agrupador × frente)</th><th>Linha de base</th><th>Situação</th><th>${r.emitido ? '' : 'Avanço verificado'}</th></tr></thead>
            <tbody>${linhas}</tbody>
          </table></div>
          <div class="cartao-rodape">Situação e percentual são informados por você. A IA local não preenche estes campos.</div>
        </section>
      </div>

      <div class="coluna-lateral">
        <div class="caixa ${r.emitido ? 'caixa-ok' : 'caixa-regra'}">
          <div class="caixa-titulo">${r.emitido ? 'Boletim emitido' : 'O que a emissão faz'}</div>
          <div>${
            r.emitido
              ? `O Boletim nº ${r.numero} passou a valer. A <a href="#/medicao">medição</a> e a <a href="#/previsao">previsão</a> já usam o que ele registra.`
              : esc(`O boletim ${r.efeito_da_emissao}`)
          }</div>
          ${r.emitido ? '' : '<div class="nota">Enquanto for rascunho, medição e previsão continuam usando o Boletim nº 7.</div>'}
        </div>
        <section class="cartao">
          <div class="cartao-titulo"><h2>Evidência do fiscal</h2><span class="nota">fotos de exemplo</span></div>
          <div class="cartao-corpo">
            <div class="fotos">
              <div class="foto">Foto 1 · 22/12 · GPS ±4 m</div>
              <div class="foto">Foto 2 · 22/12 · GPS ±4 m</div>
              <div class="foto">Foto 3 · 22/12 · GPS ±6 m</div>
            </div>
            <div class="nota">Cada foto guarda frente, serviço, data, hora, GPS e hash.</div>
          </div>
        </section>
        ${iaDesligada('Aqui aparecem os indícios de conclusão do evento (diários e fotos), com as fontes. A sugestão nunca preenche a situação nem o percentual.')}
      </div>
    </div>
  </div>`;
}

function telaMedicao() {
  const m = painel.medicao;
  if (!m.itens.some((i) => i.evento_id === eventoSelecionado)) {
    eventoSelecionado = (m.itens.find((i) => i.pendente) || m.itens[0]).evento_id;
  }
  const item = m.itens.find((i) => i.evento_id === eventoSelecionado);

  const linhas = m.itens
    .map((i) => {
      const alerta = i.glosado
        ? '<span class="pilula pilula-erro">Glosado</span>'
        : i.pendente
          ? '<span class="selo selo-regra">Regra</span>'
          : '<span style="color: var(--ok); font-weight: 600;">Sem alertas</span>';
      const classes = [i.evento_id === eventoSelecionado ? 'selecionada' : '', i.glosado ? 'riscada' : ''].join(' ');
      return `<tr class="${classes}">
        <td><button type="button" class="botao-linha" data-acao="selecionar" data-evento="${i.evento_id}">${esc(i.nome)}</button><br><small>${i.servicos.length} serviços da planilha</small></td>
        <td>${esc(i.previsto)}</td>
        <td>${pilula(i.situacao)}<br><small>${esc(i.boletim)}</small></td>
        <td class="num">${esc(i.valor)}</td>
        <td>${alerta}</td>
      </tr>`;
    })
    .join('');

  const caixaDaRegra = item.glosado
    ? `<div class="caixa caixa-regra"><div><span class="selo selo-regra">Regra</span></div><div>${esc(item.regra)}</div></div>`
    : `<div class="caixa ${item.pendente ? 'caixa-regra' : 'caixa-ok'}"><div><span class="selo selo-regra">Regra</span></div><div>${esc(item.regra)}</div>${
        item.pendente && !painel.rascunho.emitido
          ? '<div><a href="#/boletim">Abrir o Boletim de Execução nº 8 (rascunho)</a></div>'
          : ''
      }</div>`;

  const glosa = m.aprovada
    ? '<div class="nota">Medição aprovada: não aceita mais glosa.</div>'
    : item.glosado
      ? `<div class="linha-acoes"><button type="button" class="btn" data-acao="desfazer-glosa" data-evento="${item.evento_id}">Desfazer a glosa</button></div>`
      : `<div class="linha-acoes"><button type="button" class="btn btn-perigo" data-acao="glosar" data-evento="${item.evento_id}">Glosar evento</button></div>`;

  return `<div class="tela">
    <div class="cabecalho">
      <div class="cabecalho-texto">
        ${migalha()}
        <h1>Medição nº ${m.numero} <span class="pilula ${m.aprovada ? 'pilula-ok' : 'pilula-atencao'}">${esc(m.status)}</span></h1>
        <div class="subtitulo">Período ${esc(m.periodo)} · enviada pela contratada em ${esc(m.enviada_em)}</div>
      </div>
      <div class="cabecalho-acoes">
        <button type="button" class="btn btn-primario" data-acao="aprovar"${m.pode_aprovar ? '' : ' disabled'}>Aprovar medição</button>
        <div class="nota">${
          m.aprovada
            ? 'Medição aprovada é imutável.'
            : m.pode_aprovar
              ? 'Todos os eventos estão conferidos ou glosados.'
              : 'Aprovar libera quando todo evento estiver conferido ou glosado.'
        }</div>
      </div>
    </div>

    <div class="indicadores">
      ${indicador('Valor bruto da medição', 'R$ ' + m.valor_bruto)}
      ${indicador('Conferidos no boletim', m.conferidos)}
      ${indicador('Glosas lançadas', 'R$ ' + m.valor_glosado)}
      ${indicador(m.aprovada ? 'Valor aprovado' : 'Valor conferido', 'R$ ' + m.valor_conferido)}
    </div>

    <div class="duas-colunas">
      <div class="coluna-principal">
        <section class="cartao">
          <div class="cartao-titulo"><h2>Eventos declarados concluídos</h2><span class="nota">Valor de cada evento calculado a partir da planilha</span></div>
          <div class="rolagem"><table>
            <thead><tr><th>Evento (agrupador × frente)</th><th>Previsto</th><th>Boletim de Execução</th><th class="num">Valor</th><th>Alertas</th></tr></thead>
            <tbody>${linhas}</tbody>
            <tfoot><tr><td colspan="3" class="num">Total da medição</td><td class="num">${esc(m.valor_bruto)}</td><td></td></tr></tfoot>
          </table></div>
          <div class="cartao-rodape"><span class="selo selo-regra">Regra</span> verificação determinística do sistema</div>
        </section>
        <section class="cartao">
          <div class="cartao-titulo"><h2>${esc(item.nome)} · serviços do evento</h2><span class="nota">Planilha fornecida pelo órgão</span></div>
          ${tabelaDeServicos(item.servicos, 'Valor do evento', item.valor)}
          <div class="cartao-rodape">O evento é medido inteiro quando concluído.</div>
        </section>
      </div>

      <div class="coluna-lateral">
        ${caixaDaRegra}
        <section class="cartao">
          <div class="cartao-titulo"><h2>Glosa deste evento</h2></div>
          <div class="cartao-corpo">
            ${glosa}
            ${m.aprovada ? '' : `<div class="nota">Glosar retira o evento inteiro desta medição: R$ ${esc(item.valor)}. Ele pode voltar em outra medição.</div>`}
          </div>
        </section>
        ${iaDesligada('Aqui aparecem as divergências entre medição, diário, fotos e boletim, ordenadas por risco, e a minuta do motivo da glosa com as fontes.')}
      </div>
    </div>
  </div>`;
}

function telaPrevisao() {
  const p = painel.previsao;
  const linhas = p.linhas
    .map(
      (l) => `<tr>
        <td>${esc(l.nome)}<br><small>Linha de base ${esc(l.linha_de_base)}</small></td><td>${pilula(l.situacao)}</td>
        <td class="col-previsao">${
          l.situacao.codigo === 'concluido'
            ? `<span class="sem-dado">${esc(l.termino)}</span><small>${esc(l.desvio)}</small>`
            : `${esc(l.termino)}<small>${esc(l.desvio)}</small><small>${esc(l.metodo)}</small>`
        }</td>
        <td class="sem-quebra ${l.pagamento_e_previsao ? 'col-previsao' : ''}">${l.pagamento_e_previsao ? esc(l.pagamento) : `<span class="sem-dado">${esc(l.pagamento)}</span>`}</td>
        <td class="num">${esc(l.valor)}</td>
      </tr>`,
    )
    .join('');
  const meses = p.desembolso
    .map(
      (m) => `<tr><td>${esc(m.mes)}</td><td>${esc(m.eventos)}</td>
        <td class="num">${esc(m.bruto)}</td><td class="num">${esc(m.retencoes)}</td><td class="num"><strong>${esc(m.liquido)}</strong></td></tr>`,
    )
    .join('');
  const como = p.como_foi_calculado.map((c) => `<div><dt>${esc(c.rotulo)}</dt><dd>${esc(c.texto)}</dd></div>`).join('');

  return `<div class="tela">
    <div class="cabecalho"><div class="cabecalho-texto">
      ${migalha()}
      <h1>Previsão de execução e recebimentos</h1>
      <div class="subtitulo">Calculada sobre o Boletim de Execução nº ${p.boletim} (vistoria em ${esc(p.calculada_em)}) e o cronograma versão 1</div>
    </div></div>

    <div class="indicadores">
      ${indicador('Término contratual', p.termino_contratual)}
      ${indicador('término da obra', p.termino_previsto, true)}
      ${indicador('desvio', p.desvio, true)}
      ${indicador(`próximo desembolso em ${p.proximo_desembolso_data}`, 'R$ ' + p.proximo_desembolso_valor, true)}
    </div>

    <div class="duas-colunas">
      <div class="coluna-principal">
        <section class="cartao">
          <div class="cartao-titulo"><h2>Eventos: linha de base e tendência</h2><span class="nota">Colunas com fundo azul-claro são previsão</span></div>
          <div class="rolagem"><table>
            <thead><tr><th>Evento (agrupador × frente)</th><th>Situação no Boletim nº ${p.boletim}</th>
              <th class="col-previsao">Previsão · término</th><th class="col-previsao">Previsão · pagamento</th><th class="num">Valor bruto</th></tr></thead>
            <tbody>${linhas}</tbody>
          </table></div>
          <div class="cartao-rodape">Valor de cada evento vem da planilha do órgão.</div>
        </section>
        <section class="cartao">
          <div class="cartao-titulo"><h2>Desembolso previsto por mês</h2>${seloPrevisao()}<span class="nota">A empresa vê o mesmo quadro como previsão de recebimento</span></div>
          <div class="rolagem"><table>
            <thead><tr><th>Mês do pagamento</th><th>Eventos</th><th class="num">Bruto</th><th class="num">Retenções</th><th class="num">Líquido</th></tr></thead>
            <tbody>${meses}</tbody>
          </table></div>
        </section>
      </div>

      <div class="coluna-lateral">
        <div class="caixa caixa-previsao">
          <div class="caixa-titulo">${RELOGIO} Como foi calculado</div>
          <dl class="lista-definicao">${como}</dl>
        </div>
        ${iaDesligada('Aqui a IA explica o cálculo em texto, citando as fontes. Ela só explica: todo número do texto tem que vir do cálculo, senão o texto é descartado.')}
        <div class="caixa caixa-desenho">
          <div class="caixa-titulo">O que a previsão não faz</div>
          <div>É estimativa calculada pelo sistema. Não altera prazo, medição nem pagamento, e não cria direito a recebimento.</div>
        </div>
      </div>
    </div>
  </div>`;
}

/** Tela que ainda é só desenho: HTML fixo, vindo do canvas de telas. */
async function telaDeDesenho(caminho) {
  if (!fragmentos.has(caminho)) {
    const resposta = await fetch(caminho);
    if (!resposta.ok) throw new Error(`Não foi possível abrir ${caminho}.`);
    fragmentos.set(caminho, await resposta.text());
  }
  return `<div class="tela tela-faixa">
    <div class="caixa caixa-desenho">
      <div class="caixa-titulo">Desenho estático</div>
      <div>Esta tela ainda não tem regra ligada. Os números são de exemplo, fixos, e os botões não fazem nada.</div>
    </div>
  </div><div class="desenho">${fragmentos.get(caminho)}</div>`;
}

const TELAS = {
  inicio: { usuario: '', desenhar: telaInicio },
  eventos: { usuario: 'Ana Prado · Planejamento', desenhar: telaEventos },
  boletim: { usuario: 'Maria Souza · Fiscal', desenhar: telaBoletim },
  medicao: { usuario: 'Maria Souza · Fiscal', desenhar: telaMedicao },
  'medicao-bm': { usuario: 'Maria Souza · Fiscal', desenhar: () => telaDeDesenho('telas/medicao-bm.html') },
  previsao: { usuario: 'Carlos Lima · Secretário de Obras', desenhar: telaPrevisao },
  painel: { usuario: 'Carlos Lima · Secretário de Obras', desenhar: () => telaDeDesenho('telas/painel.html') },
  'console-ia': { usuario: 'Rafael Alves · Informática', desenhar: () => telaDeDesenho('telas/console-ia.html') },
};

// ----------------------------------------------------------------- navegação

const telaAtual = () => {
  const nome = location.hash.replace(/^#\/?/, '');
  return TELAS[nome] ? nome : 'inicio';
};

async function desenhar({ manterRolagem = false } = {}) {
  const nome = telaAtual();
  const rolagem = conteudo.scrollTop;
  try {
    conteudo.innerHTML = await TELAS[nome].desenhar();
  } catch (erro) {
    conteudo.innerHTML = `<div class="tela"><div class="caixa caixa-regra"><div class="caixa-titulo">Não foi possível mostrar esta tela</div><div>${esc(erro.message || erro)}</div></div></div>`;
  }
  // Nas telas de desenho, o que depende do estado é preenchido por `data-bind`.
  conteudo.querySelectorAll('[data-bind]').forEach((no) => {
    const valor = no.dataset.bind.split('.').reduce((o, chave) => (o == null ? o : o[chave]), painel);
    if (valor != null) no.textContent = valor;
  });
  usuario.textContent = TELAS[nome].usuario;
  document.querySelectorAll('.lateral a').forEach((a) => {
    if (a.getAttribute('href') === `#/${nome}`) a.setAttribute('aria-current', 'page');
    else a.removeAttribute('aria-current');
  });
  conteudo.scrollTop = manterRolagem ? rolagem : 0;
}

function avisar(texto, erro = false) {
  aviso.textContent = texto;
  aviso.className = erro ? 'erro' : '';
  clearTimeout(temporizadorDoAviso);
  temporizadorDoAviso = setTimeout(() => (aviso.textContent = ''), erro ? 9000 : 5000);
}

/** Ação irreversível: diálogo com a consequência escrita. */
function confirmar(titulo, texto, rotulo) {
  document.getElementById('confirmar-titulo').textContent = titulo;
  document.getElementById('confirmar-texto').textContent = texto;
  document.getElementById('confirmar-sim').textContent = rotulo;
  dialogo.returnValue = 'cancelar';
  dialogo.showModal();
  return new Promise((resolver) => {
    dialogo.addEventListener('close', () => resolver(dialogo.returnValue === 'confirmar'), { once: true });
  });
}

/** Executa um comando do Rust, que devolve as telas recalculadas. */
async function executar(comando, argumentos, mensagem) {
  try {
    painel = await invocar(comando, argumentos);
    if (mensagem) avisar(mensagem);
  } catch (erro) {
    avisar(String(erro), true);
  }
  await desenhar({ manterRolagem: true });
}

async function aoClicar(evento) {
  const linkVazio = evento.target.closest('a[href="#"]');
  if (linkVazio) {
    evento.preventDefault();
    return;
  }
  const alvo = evento.target.closest('[data-acao]');
  if (!alvo) return;
  const idDoEvento = Number(alvo.dataset.evento);
  switch (alvo.dataset.acao) {
    case 'selecionar':
      eventoSelecionado = idDoEvento;
      await desenhar({ manterRolagem: true });
      break;
    case 'glosar':
      await executar('glosar_evento', { evento: idDoEvento }, 'Evento glosado. Ele saiu desta medição e pode voltar em outra.');
      break;
    case 'desfazer-glosa':
      await executar('desfazer_glosa', { evento: idDoEvento }, 'Glosa desfeita.');
      break;
    case 'emitir':
      const consequencia = `Você está emitindo o Boletim de Execução nº 8. Ele ${painel.rascunho.efeito_da_emissao}`;
      if (await confirmar('Emitir o Boletim de Execução nº 8?', consequencia, 'Emitir e assinar')) {
        await executar('emitir_boletim', undefined, 'Boletim de Execução nº 8 emitido. Medição e previsão foram recalculadas.');
      }
      break;
    case 'aprovar':
      if (await confirmar('Aprovar a Medição nº 3?', painel.medicao.confirmacao_da_aprovacao, 'Aprovar medição')) {
        await executar('aprovar_medicao', undefined, 'Medição nº 3 aprovada.');
      }
      break;
    case 'reiniciar':
      eventoSelecionado = null;
      await executar('reiniciar', undefined, 'Demonstração reiniciada.');
      break;
    default:
  }
}

async function aoMudarCampo(evento) {
  const campo = evento.target.dataset.campo;
  if (!campo) return;
  const situacao = campo === 'situacao' ? evento.target.value : painel.rascunho.situacao;
  const digitado = campo === 'avanco' ? Number(evento.target.value.replace(',', '.')) : painel.rascunho.avanco;
  if (!Number.isInteger(digitado) || digitado < 0 || digitado > 255) {
    avisar('Informe o avanço como um número inteiro de 1 a 99.', true);
    await desenhar({ manterRolagem: true });
    return;
  }
  await executar('salvar_rascunho', { situacao, avanco: digitado });
}

document.addEventListener('click', aoClicar);
conteudo.addEventListener('change', aoMudarCampo);
window.addEventListener('hashchange', () => desenhar());

(async () => {
  try {
    painel = await invocar('painel');
  } catch (erro) {
    conteudo.innerHTML = `<div class="tela"><div class="caixa caixa-regra"><div class="caixa-titulo">O Prumo não conseguiu iniciar</div><div>${esc(erro)}</div></div></div>`;
    return;
  }
  await desenhar();
})();
