# Logo transparente do painel

A logo usada por `BrandLogo` tem fundo transparente nos dois temas. Sidebar,
Login e cabeçalho compacto selecionam a versão apropriada automaticamente.
O arquivo original continua disponível como referência da marca.

## Arquivos aplicados

- Tema claro: `admin_web/assets/brand/ponto_aqui_logo_transparent.png`.
- Tema escuro: `admin_web/assets/brand/ponto_aqui_logo_dark.png`.
- Componente: `admin_web/lib/views/widgets/brand_logo.dart`.

Ferramenta: `image_gen.imagegen` integrada, com `transparent_background=true`.
Os PNGs possuem canal alfa; o tema escuro usa azul mais claro para manter a
legibilidade da marca sobre a Sidebar escura. Não foi usado o CLI da API.

## Prompts utilizados

### Favicon transparente do navegador

O arquivo `admin_web/web/icons/favicon-transparent.png` é usado pelo `rel="icon"` em `admin_web/web/index.html`. Possui canal alfa e substitui, na aba do navegador, a versão com fundo branco. O nome novo também evita reutilizar o favicon antigo em cache. O ícone original permanece no projeto.

Gerado pela ferramenta integrada `image_gen.imagegen`, com `transparent_background=true`, usando `admin_web/web/icons/brand-symbol.png` como imagem de edição. Não foi usado o CLI da API.

```text
Use case: background-extraction. Asset type: production favicon for the existing Ponto Aqui Flutter Web administrative dashboard. Edit target: the referenced square clock/map-pin/checkmark logo image. Remove ONLY all white background to genuine transparent alpha, including the large outer square and the white negative spaces inside the clock, between the two pin sections, and around the artwork. Preserve the existing exact geometry, navy blue and teal palette, subtle gradients, clock ticks and checkmark. No redesign, no text, no new elements, no shadows, no white halo or matte, no checkerboard drawn into the pixels. Keep the complete emblem centered on a square canvas, with a small even transparent margin and sharp clean edges so it remains legible at 16x16 and 32x32 browser-tab sizes. Output a transparent PNG. The image must have real transparent pixels, not a black or white background.
```

### Tema claro

```text
Use case: background-extraction. Edit target: the supplied original Ponto Aqui brand logo. Remove ONLY the white background to true transparent alpha, including white whitespace around the logo, white negative spaces inside letter counters and inside the clock/map pin. Preserve exactly the original spelling 'Ponto Aqui', custom letterforms, clock/map-pin checkmark emblem, positions, proportions, navy-blue and teal colors, gradients and edge sharpness. Do not redesign, recolor, add shadows, add borders, add white halo or add any elements. Output a tightly framed wide horizontal transparent PNG around the existing artwork with a small transparent safety margin. This is a production logo asset for an existing Flutter administrative dashboard, shown over both white and dark-gray surfaces. Maintain source logo geometry and typography faithfully.
```

### Tema escuro

```text
Use case: background-extraction. Asset: dark-mode transparent PNG variant of the EXISTING Ponto Aqui logo, not a new logo. Edit target is the exact provided logo. Remove all the white background to real transparent alpha, including white spaces inside the clock symbol and letter counters. Preserve exactly the clock/map pin/checkmark shape, typography, spelling 'Ponto Aqui', relative layout, proportions and original teal/aqua portions. Only lighten the navy-blue portions (the left section of the location/clock emblem and the letters Ponto) to pale blue #A8D0F5 for accessible legibility against a #1E1E1E dark-gray Flutter Sidebar. Lighten the gray clock ticks to a soft blue-gray. Keep original teal 'Aqui', teal checkmark and teal emblem section. No redesign, no additional shapes, no text changes, no backgrounds, no white patch behind the emblem, no drop shadows, no halo or outlined edges. Output wide horizontal canvas tightly framing the logo plus small even transparent margin; pristine clean antialiased transparent edges.
```

### Refinamento do tema escuro

```text
Edit this existing transparent Ponto Aqui logo. Precision cleanup only: eliminate EVERY white residual fragment, white streak, ghost edge, noise speck and ragged cutout artifact around and within all letters and the emblem. The logo should look like a pristine vector logo exported to a transparent PNG: smooth solid clean edges and uniform opaque artwork, absolutely no leftover white matte. Preserve the exact existing geometry, layout, clock tick positions, location-pin silhouette, checkmark and text 'Ponto Aqui'. Keep the Ponto lettering and blue portion of the icon PALE BLUE #A8D0F5; keep Aqui and other teal portions #00AAA0; clock ticks muted blue-gray. No background; all negative spaces and all surrounding canvas truly transparent; no white pixels or shadows. Frame complete logo with small even transparent margin. This is a small dark-mode sidebar logo, crisp and legible, so stray white fragments must be gone.
```
