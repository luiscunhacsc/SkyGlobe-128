# SkyGlobe 128 — versão 0.2.1

Planetário **nativo em Z80 para o ZX Spectrum 128K**, inspirado na interface do SkyGlobe para DOS da imagem de referência. O programa é uma fita TAP autónoma; o emulador incluído permite experimentá-lo no navegador.

## Experimentar

1. Extraia o ZIP para uma pasta.
2. Abra **index.html**, ou use o lançador do seu sistema operativo.
3. Carregue em **Iniciar SkyGlobe 128**. A seleção do modelo 128K, a inserção da fita e o Enter no Tape Loader são automáticos.
4. Aguarde o primeiro mapa. Clique no ecrã para lhe dar o foco do teclado.

O HTML funciona sem ligação à Internet. O botão **Large view / F3** aumenta a área de apresentação; **Fullscreen / F2** ocupa o ecrã. A tecla **F1** continua a abrir o mapa de teclado do emulador; a ajuda do planetário abre com **1**.

Para usar outro emulador, selecione o modelo **128K**, insira **SKYGLOBE128.tap** e escolha **Tape Loader**. A fita contém o carregador BASIC, o programa Z80 e os cinco bancos de dados. O programa usa paginação de memória e requer o modelo 128K.

## A vista de referência

A vista inicial usa **Caledonia, Michigan, 24 de março de 2025, 10:42 UTC**, direção sul e elevação de 45°. Para aproximar a distribuição das estrelas da imagem, as 05:42 do exemplo são interpretadas no fuso UTC−5. O Spectrum apresenta sempre UTC. A tecla **0** repõe esta vista e as opções iniciais.

**L** muda de Caledonia para **Coimbra**, Lisboa, Greenwich, Sydney e o Equador. **Ctrl+L** percorre os locais no sentido contrário. As coordenadas são predefinidas nesta versão.

## Comandos

No Spectrum, **Caps Shift** ou **Symbol Shift** invertem os ajustes. No PC, use **Ctrl** ou **Shift**. As setas do PC correspondem aos cursores Spectrum: Caps Shift + 5/6/7/8.

| Tecla | Função |
|---|---|
| Setas ou 5 / 6 / 7 / 8 | Rodar para a esquerda / baixar / subir / rodar para a direita; o passo diminui ao aproximar |
| N / S / E / W | Norte / sul / este / oeste |
| Z | Percorrer nove níveis de zoom, até 64; Shift+Z recua |
| B | Limite de magnitude: 2,0; 3,0; 4,0; 4,5; 5,0; 5,5; 6,0 |
| C | Linhas das constelações |
| O | Abreviaturas das constelações |
| K | Via Láctea |
| V | Horizonte |
| G | Meridianos de ascensão reta |
| 3 / 4 | Equador celeste / eclíptica |
| P | Sol, Lua e sete planetas |
| U | Os 110 objetos Messier |
| I | Projeção estereográfica / ortográfica |
| X | Espelhar a imagem |
| Enter | Mira central |
| F | Procurar objeto pelo nome |
| J | Voltar a centrar o objeto selecionado |
| H / T | Avançar uma hora / um minuto |
| D / M / Y | Avançar um dia / um mês / um ano |
| L | Próximo local predefinido |
| A ou Espaço | Iniciar/parar animação, cinco minutos por mapa; Shift+A inicia no sentido inverso |
| R | Relógio contado a 50 Hz, a partir da data e hora apresentadas |
| 1 / 2 / 9 | Ajuda / mostrar dados / mostrar comandos |
| 0 | Repor a vista de referência |
| Q | Regressar ao menu da ROM 128K |

Os ajustes de hora, dia, mês, ano, local, brilho e zoom também funcionam no sentido inverso com Shift. A animação avança à medida que cada novo mapa fica pronto. O modo R mantém o tempo decorrido durante os cálculos, atualizando o minuto apresentado quando necessário.

O redesenho demora alguns segundos à velocidade original do Spectrum. Uma tecla breve premida durante esse trabalho fica guardada pela interrupção e é atendida a seguir. Essa memória guarda **uma** tecla.

## Pesquisa

Prima **F** e escreva parte do nome: por exemplo `VEGA`, `ORION`, `M31`, `ANDROMEDA` ou `MOON`. A pesquisa abrange **288 entradas** e apresenta os primeiros doze resultados. Acrescente letras para restringir a lista.

- **Seta para baixo / Caps Shift+6:** próximo resultado.
- **Seta para cima / Caps Shift+7:** resultado anterior.
- **Enter:** centrar o objeto e voltar ao mapa.
- **Ctrl+0 / Caps Shift+0:** apagar a última letra.
- **Ctrl+1 / Caps Shift+1:** sair da pesquisa.

Os nomes astronómicos são internacionais e aparecem em maiúsculas. O texto de ajuda está em português; a coluna de comandos mantém a apresentação e o vocabulário próximos do original.

## A Lua e as suas fases

A Lua é desenhada como um **disco proporcional à escala angular do mapa**. O tamanho varia com o zoom, a projeção e a distância geocêntrica da Lua naquela data. A parte iluminada resulta da geometria Sol–Lua–Terra, com um terminador curvo; acompanha a orientação da vista e a opção de espelho.

Para observar: prima **F**, escreva **MOON**, prima **Enter** e aproxime com **Z**. Os níveis 16, 32 e 64 permitem distinguir as fases com mais detalhe. **J** volta a centrar a Lua depois de mudar a data ou deslocar a vista.

Na vista inicial, o diâmetro lunar ocupa aproximadamente **um píxel**; no zoom 64, ronda **31–35 píxeis** quando a Lua está centrada. No nível mais afastado, pode ficar abaixo de um píxel. O programa arredonda o diâmetro ao píxel mais próximo e mantém o nome para permitir localizar o objeto. O lado não iluminado oculta as estrelas que estejam atrás dele. Não se acrescenta um contorno luminoso à Lua nova.

O desenho representa a fase e a silhueta esférica, sem textura de crateras ou simulação de eclipses. As mesmas cores e limitações de atributos da ULA aplicam-se ao disco.

## Conteúdo e limites desta versão

- **5044 estrelas reais**, até magnitude 6,0, com tamanhos diferentes para as mais brilhantes. O número no canto superior esquerdo conta as estrelas do catálogo admitidas pelo limite de magnitude, incluindo as que estão fora da vista.
- **88 constelações**, com 743 segmentos, nomes abreviados e pesquisa pelo nome completo. Serpens tem duas regiões no catálogo de desenho.
- **110 objetos Messier**, com marcas e identificação.
- **Via Láctea** baseada no contorno publicado, reduzido a manchas de cor de 8 × 8 píxeis. Os detalhes das faixas escuras são simplificados.
- **Sol, Lua, Mercúrio, Vénus, Marte, Júpiter, Saturno, Úrano e Neptuno**, com amostras diárias e interpolação das posições no próprio Z80. A Lua tem disco, fases, orientação da iluminação e diâmetro angular próprios.
- Calendário de **1 de janeiro de 2025 a 31 de dezembro de 2028**, incluindo 29 de fevereiro de 2028. Ao ultrapassar as extremidades, o calendário volta ao outro extremo desse intervalo.
- Indicadores no canto superior esquerdo com **quatro píxeis de margem** em cima e à esquerda.
- **256 × 192 píxeis**, cores e atributos normais da ULA. A fonte tem glifos de **3 × 5** numa grelha de **4 × 6**, permitindo **64 colunas**. O atributo de cada bloco de 8 × 8 é partilhado por estrelas, linhas e texto; as mudanças locais de cor fazem parte da apresentação nativa.

As posições são aproximadas: vetores compactos de oito bits, coordenadas J2000, sem correção de precessão, nutação, refração atmosférica ou paralaxe topocêntrica. A Lua também usa a posição geocêntrica. A quantização torna-se mais visível com zoom elevado. Os objetos abaixo do horizonte continuam desenhados, como na apresentação da referência.

O modo R usa as interrupções da máquina, sem acesso ao relógio do PC. A disponibilidade de impressão, configurações gravadas, locais personalizados e datas fora de 2025–2028 fica para versões posteriores.

## Ficheiros e reconstrução

| Caminho | Conteúdo |
|---|---|
| `index.html` | Emulador completo e autónomo, com a fita embutida |
| `SKYGLOBE128.tap` | Programa nativo para Spectrum 128K |
| `PREVIEW.png` | Imagem do ecrã nativo inicial, ampliada sem suavização |
| `MOON_PREVIEW.png` | Lua no mapa com zoom 64, mantendo a escala angular |
| `source/skyglobe.asm` | Motor, desenho, comandos, pesquisa e interrupção |
| `source/moon.asm` | Geometria da iluminação e desenho proporcional do disco lunar |
| `source/loader.asm` | Carregador nativo dos bancos pela ROM |
| `source/state.inc` | Mensagens, fonte de configuração e estado inicial |
| `source/build.py` | Conversão dos catálogos, efemérides e construção da fita |
| `source/generated.inc` | Fonte de letra, tabela trigonométrica e constantes geradas |
| `data/` | Catálogos de origem e respetiva licença |
| `build/` | Binários dos bancos, símbolos, catálogo de proveniência e validação |
| `developer/` | Código e testes do emulador original, com o lançamento SkyGlobe acrescentado |

Com Python 3 e Node.js disponíveis, execute a partir desta pasta:

```sh
python -m pip install -r source/requirements.txt
python source/build.py
node --test developer/tests/*.test.cjs
```

Para voltar a montar o código sem recalcular os dados, use `python source/build.py --assemble-only`. A geração do HTML também pode ser feita com `python developer/build_single_html.py`; mantém-se o script PowerShell original.

O programa usa os bancos 0 e 1 para estrelas e geometria, 3/4/6 para efemérides e 7 para o ecrã de apresentação. A zona livre do banco 6 guarda também os dados lunares de iluminação e semi-diâmetro angular. As matrizes, os cálculos, a projeção, a pesquisa, a interpolação e o desenho do disco por píxel correm no processador Z80. O JavaScript emula a máquina e automatiza apenas o arranque pela ROM.

## Fontes e licenças

- Catálogos e geometrias de [d3-celestial, Olaf Frohn](https://github.com/ofrohn/d3-celestial), sob licença BSD de três cláusulas, reproduzida em `data/LICENSE`. Os dados estelares desse projeto derivam do XHIP; os contornos da Via Láctea são creditados a José R. Vieira. As transformações e a redução dos dados estão em `source/build.py`; os hashes dos ficheiros originais estão em `build/catalogue.json`.
- Efemérides calculadas com [Astronomy Engine, Don Cross](https://github.com/cosinekitty/astronomy), versão 2.1.19, licença MIT. Usa-se `GeoVector` no referencial equatorial J2000. O programa nativo interpola as amostras diárias guardadas nos bancos.
- O diâmetro angular da Lua usa o raio médio de **1737,4 km** da [Moon Fact Sheet, NASA/NSSDCA](https://nssdc.gsfc.nasa.gov/planetary/factsheet/moonfact.html), combinado com a distância calculada pelas efemérides. A validação inclui oito fases de janeiro de 2026 e comparação com `Illumination` do Astronomy Engine.
- Montagem com [pyz80](https://github.com/simonowen/pyz80), versão 1.3.0. O montador é uma dependência de construção.
- O emulador fornecido mantém a sua licença e atribuições em `LICENSE-emulator.txt`, incluindo o núcleo Z80 de Molly Howell. As ROMs e fitas previamente incluídas são preservadas.
- O código novo do planetário está sob a licença MIT em `LICENSE.txt`.

Implementação original, inspirada na interface da imagem fornecida.
