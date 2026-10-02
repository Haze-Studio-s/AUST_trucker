/**
 * NEXUS OS - AUTHENTIC macOS SKEUOMORPHIC/FLAT-HYBRID SVG ICON SYSTEM
 * Ícones vetoriais de altíssima fidelidade inspirados no padrão Apple macOS Sonoma/Sequoia.
 * Substitui ícones genéricos de FontAwesome por ilustrações com camadas, sombras e reflexos.
 */

window.NexusIcons = (function() {
    'use strict';

    const ICONS = {
        // 1. FINDER (O icônico rosto split-tone azul/ciano com sorriso do macOS)
        finder: `
            <svg viewBox="0 0 100 100" class="w-full h-full select-none" xmlns="http://www.w3.org/2000/svg">
                <defs>
                    <linearGradient id="nx-finder-bg" x1="0%" y1="0%" x2="0%" y2="100%">
                        <stop offset="0%" stop-color="#4db2ff"/>
                        <stop offset="100%" stop-color="#026be4"/>
                    </linearGradient>
                    <linearGradient id="nx-finder-face-left" x1="0%" y1="0%" x2="100%" y2="0%">
                        <stop offset="0%" stop-color="#d4ebff"/>
                        <stop offset="100%" stop-color="#80c6ff"/>
                    </linearGradient>
                    <linearGradient id="nx-finder-glass" x1="0%" y1="0%" x2="0%" y2="100%">
                        <stop offset="0%" stop-color="#ffffff" stop-opacity="0.45"/>
                        <stop offset="35%" stop-color="#ffffff" stop-opacity="0.08"/>
                        <stop offset="100%" stop-color="#ffffff" stop-opacity="0"/>
                    </linearGradient>
                    <filter id="nx-finder-shadow" x="-10%" y="-10%" width="120%" height="125%">
                        <feDropShadow dx="0" dy="2" stdDeviation="1.5" flood-color="#00224d" flood-opacity="0.35"/>
                    </filter>
                </defs>
                <!-- Squircle Base -->
                <rect x="4" y="4" width="92" height="92" rx="22" fill="url(#nx-finder-bg)"/>
                <!-- Glass Specular Highlight Top -->
                <rect x="5" y="5" width="90" height="42" rx="21" fill="url(#nx-finder-glass)"/>
                <!-- Inner Border / Bevel -->
                <rect x="4.5" y="4.5" width="91" height="91" rx="21.5" fill="none" stroke="rgba(255,255,255,0.4)" stroke-width="1.2"/>

                <!-- Finder Left Split Face -->
                <path d="M 22 23 C 22 23, 48 22, 50 22 C 50 48, 51 54, 43 58 C 43 62, 45 68, 50 68 C 47 77, 30 77, 22 75 Z" fill="url(#nx-finder-face-left)"/>

                <!-- Face Features with Depth Shadow -->
                <g filter="url(#nx-finder-shadow)">
                    <!-- Left Eye -->
                    <ellipse cx="36" cy="41" rx="3.4" ry="4.5" fill="#002454"/>
                    <!-- Right Eye -->
                    <ellipse cx="64" cy="41" rx="3.4" ry="4.5" fill="#002454"/>
                    <!-- Nose Line (Partição ondulada clássica) -->
                    <path d="M 50 22 C 50 47, 51 54, 43 58 C 43 62, 45 68, 50 68" fill="none" stroke="#002454" stroke-width="4.2" stroke-linecap="round" stroke-linejoin="round"/>
                    <!-- Smiling Mouth -->
                    <path d="M 32 64 C 40 76, 60 76, 68 64" fill="none" stroke="#002454" stroke-width="4.2" stroke-linecap="round"/>
                </g>
            </svg>
        `,

        // 2. SAFARI / BROWSER (Bússola náutica refinada com agulha 3D e anel metálico)
        browser: `
            <svg viewBox="0 0 100 100" class="w-full h-full select-none" xmlns="http://www.w3.org/2000/svg">
                <defs>
                    <linearGradient id="nx-safari-bg" x1="0%" y1="0%" x2="0%" y2="100%">
                        <stop offset="0%" stop-color="#ffffff"/>
                        <stop offset="100%" stop-color="#dce4ec"/>
                    </linearGradient>
                    <radialGradient id="nx-safari-dial" cx="50%" cy="50%" r="50%">
                        <stop offset="0%" stop-color="#1ea6fc"/>
                        <stop offset="65%" stop-color="#0b63e8"/>
                        <stop offset="100%" stop-color="#043ca6"/>
                    </radialGradient>
                    <linearGradient id="nx-needle-red" x1="0%" y1="0%" x2="100%" y2="100%">
                        <stop offset="0%" stop-color="#ff453a"/>
                        <stop offset="100%" stop-color="#d61f1f"/>
                    </linearGradient>
                    <linearGradient id="nx-needle-white" x1="0%" y1="0%" x2="100%" y2="100%">
                        <stop offset="0%" stop-color="#ffffff"/>
                        <stop offset="100%" stop-color="#cbd5e1"/>
                    </linearGradient>
                    <filter id="nx-needle-shadow">
                        <feDropShadow dx="1" dy="2" stdDeviation="1.5" flood-color="#001844" flood-opacity="0.45"/>
                    </filter>
                </defs>
                <!-- Squircle Base -->
                <rect x="4" y="4" width="92" height="92" rx="22" fill="url(#nx-safari-bg)"/>
                <rect x="4.5" y="4.5" width="91" height="91" rx="21.5" fill="none" stroke="rgba(255,255,255,0.8)" stroke-width="1.2"/>

                <!-- Dial Outer Bezel -->
                <circle cx="50" cy="50" r="39" fill="url(#nx-safari-dial)"/>
                <circle cx="50" cy="50" r="39" fill="none" stroke="#ffffff" stroke-width="1.2" stroke-opacity="0.6"/>
                <circle cx="50" cy="50" r="35" fill="none" stroke="rgba(255,255,255,0.22)" stroke-width="0.8" stroke-dasharray="2 3"/>

                <!-- Compass Tick Marks (Degree lines) -->
                <g stroke="rgba(255,255,255,0.6)" stroke-width="1" stroke-linecap="round">
                    <line x1="50" y1="13" x2="50" y2="17"/>
                    <line x1="50" y1="83" x2="50" y2="87"/>
                    <line x1="13" y1="50" x2="17" y2="50"/>
                    <line x1="83" y1="50" x2="87" y2="50"/>
                    <!-- 45-deg ticks -->
                    <line x1="24" y1="24" x2="27" y2="27"/>
                    <line x1="76" y1="76" x2="73" y2="73"/>
                    <line x1="76" y1="24" x2="73" y2="27"/>
                    <line x1="24" y1="76" x2="27" y2="73"/>
                </g>

                <!-- Magnetic Needle 3D -->
                <g filter="url(#nx-needle-shadow)" transform="rotate(-35 50 50)">
                    <!-- North (Red) -->
                    <polygon points="50,16 55.5,50 50,47" fill="#ff6961"/>
                    <polygon points="50,16 44.5,50 50,47" fill="url(#nx-needle-red)"/>
                    <!-- South (White) -->
                    <polygon points="50,84 55.5,50 50,53" fill="url(#nx-needle-white)"/>
                    <polygon points="50,84 44.5,50 50,53" fill="#94a3b8"/>
                    <!-- Center Pin -->
                    <circle cx="50" cy="50" r="4.2" fill="#e2e8f0"/>
                    <circle cx="50" cy="50" r="2" fill="#1e293b"/>
                </g>
            </svg>
        `,

        // 3. APP STORE (Azul vibrante com a letra 'A' formada por régua, lápis e pincel)
        app_store: `
            <svg viewBox="0 0 100 100" class="w-full h-full select-none" xmlns="http://www.w3.org/2000/svg">
                <defs>
                    <linearGradient id="nx-store-bg" x1="0%" y1="0%" x2="0%" y2="100%">
                        <stop offset="0%" stop-color="#1ea0ff"/>
                        <stop offset="100%" stop-color="#0263e0"/>
                    </linearGradient>
                    <linearGradient id="nx-store-sheen" x1="0%" y1="0%" x2="0%" y2="100%">
                        <stop offset="0%" stop-color="#ffffff" stop-opacity="0.38"/>
                        <stop offset="40%" stop-color="#ffffff" stop-opacity="0.05"/>
                        <stop offset="100%" stop-color="#ffffff" stop-opacity="0"/>
                    </linearGradient>
                    <filter id="nx-store-shadow">
                        <feDropShadow dx="0" dy="3" stdDeviation="2.5" flood-color="#002663" flood-opacity="0.45"/>
                    </filter>
                </defs>
                <rect x="4" y="4" width="92" height="92" rx="22" fill="url(#nx-store-bg)"/>
                <rect x="5" y="5" width="90" height="42" rx="21" fill="url(#nx-store-sheen)"/>
                <rect x="4.5" y="4.5" width="91" height="91" rx="21.5" fill="none" stroke="rgba(255,255,255,0.4)" stroke-width="1.2"/>

                <!-- White Glowing 'A' Made of Creative Tools -->
                <g filter="url(#nx-store-shadow)" stroke="#ffffff" stroke-linecap="round" stroke-linejoin="round">
                    <!-- Left Bar: Ruler -->
                    <line x1="33" y1="78" x2="67" y2="22" stroke-width="8" stroke="#ffffff"/>
                    <!-- Right Bar: Pencil -->
                    <line x1="67" y1="78" x2="33" y2="22" stroke-width="8" stroke="#ffffff"/>
                    <!-- Horizontal Bar: Paintbrush -->
                    <line x1="24" y1="61" x2="76" y2="61" stroke-width="8" stroke="#ffffff"/>
                </g>
                <!-- Detail lines on the tools -->
                <g stroke="#0263e0" stroke-width="1.5" opacity="0.65" stroke-linecap="round">
                    <line x1="30" y1="61" x2="30" y2="65"/>
                    <line x1="34" y1="61" x2="34" y2="64"/>
                    <line x1="38" y1="61" x2="38" y2="65"/>
                    <line x1="62" y1="61" x2="62" y2="64"/>
                    <line x1="66" y1="61" x2="66" y2="65"/>
                    <line x1="70" y1="61" x2="70" y2="64"/>
                </g>
            </svg>
        `,

        // 4. SETTINGS / AJUSTES (Engrenagens mecânicas metálicas de titânio acetinado)
        settings: `
            <svg viewBox="0 0 100 100" class="w-full h-full select-none" xmlns="http://www.w3.org/2000/svg">
                <defs>
                    <linearGradient id="nx-settings-bg" x1="0%" y1="0%" x2="0%" y2="100%">
                        <stop offset="0%" stop-color="#8e8e93"/>
                        <stop offset="50%" stop-color="#636366"/>
                        <stop offset="100%" stop-color="#3a3a3c"/>
                    </linearGradient>
                    <linearGradient id="nx-gear-silver" x1="0%" y1="0%" x2="100%" y2="100%">
                        <stop offset="0%" stop-color="#ffffff"/>
                        <stop offset="45%" stop-color="#c7c7cc"/>
                        <stop offset="100%" stop-color="#8e8e93"/>
                    </linearGradient>
                    <filter id="nx-gear-shadow">
                        <feDropShadow dx="0" dy="3" stdDeviation="2.5" flood-color="#1c1c1e" flood-opacity="0.6"/>
                    </filter>
                </defs>
                <rect x="4" y="4" width="92" height="92" rx="22" fill="url(#nx-settings-bg)"/>
                <rect x="4.5" y="4.5" width="91" height="91" rx="21.5" fill="none" stroke="rgba(255,255,255,0.25)" stroke-width="1.2"/>

                <!-- Main Metallic Gear -->
                <g filter="url(#nx-gear-shadow)">
                    <!-- Gear Teeth Outer Body -->
                    <circle cx="50" cy="50" r="32" fill="url(#nx-gear-silver)"/>
                    <!-- 12 Mechanical Teeth -->
                    <path d="
                        M 45 13 L 55 13 L 54 22 L 46 22 Z
                        M 45 87 L 55 87 L 54 78 L 46 78 Z
                        M 13 45 L 13 55 L 22 54 L 22 46 Z
                        M 87 45 L 87 55 L 78 54 L 78 46 Z
                        M 24 24 L 31 17 L 37 25 L 30 32 Z
                        M 76 76 L 69 83 L 63 75 L 70 68 Z
                        M 76 24 L 83 31 L 75 37 L 68 30 Z
                        M 24 76 L 17 69 L 25 63 L 32 70 Z
                    " fill="url(#nx-gear-silver)"/>
                    <!-- Inner Recess with Shading -->
                    <circle cx="50" cy="50" r="22" fill="#48484a"/>
                    <circle cx="50" cy="50" r="18" fill="url(#nx-gear-silver)"/>
                    <circle cx="50" cy="50" r="11" fill="#2c2c2e"/>
                    <circle cx="50" cy="50" r="8" fill="#1c1c1e"/>
                </g>
            </svg>
        `,

        // 5. NOTES / BLOCO DE NOTAS (Bloco pautado amarelo com fita de couro costurada e lápis)
        notes: `
            <svg viewBox="0 0 100 100" class="w-full h-full select-none" xmlns="http://www.w3.org/2000/svg">
                <defs>
                    <linearGradient id="nx-notes-bg" x1="0%" y1="0%" x2="0%" y2="100%">
                        <stop offset="0%" stop-color="#fff8db"/>
                        <stop offset="100%" stop-color="#fef0b8"/>
                    </linearGradient>
                    <linearGradient id="nx-notes-header" x1="0%" y1="0%" x2="0%" y2="100%">
                        <stop offset="0%" stop-color="#f59e0b"/>
                        <stop offset="100%" stop-color="#d97706"/>
                    </linearGradient>
                    <filter id="nx-notes-shadow">
                        <feDropShadow dx="0" dy="2" stdDeviation="1.5" flood-color="#78350f" flood-opacity="0.3"/>
                    </filter>
                </defs>
                <rect x="4" y="4" width="92" height="92" rx="22" fill="url(#nx-notes-bg)"/>
                <rect x="4.5" y="4.5" width="91" height="91" rx="21.5" fill="none" stroke="rgba(217, 119, 6, 0.3)" stroke-width="1.2"/>

                <!-- Top Stitched Leather Tape Header -->
                <path d="M 4 22 C 4 12, 12 4, 22 4 L 78 4 C 88 4, 96 12, 96 22 L 96 27 L 4 27 Z" fill="url(#nx-notes-header)"/>
                <!-- Perforated paper dots -->
                <g fill="#b45309" opacity="0.6">
                    <circle cx="16" cy="27" r="1.5"/><circle cx="28" cy="27" r="1.5"/>
                    <circle cx="40" cy="27" r="1.5"/><circle cx="52" cy="27" r="1.5"/>
                    <circle cx="64" cy="27" r="1.5"/><circle cx="76" cy="27" r="1.5"/>
                    <circle cx="88" cy="27" r="1.5"/>
                </g>

                <!-- Horizontal Ruled Blue Lines -->
                <g stroke="#93c5fd" stroke-width="1.4" opacity="0.75" stroke-linecap="round">
                    <line x1="16" y1="38" x2="84" y2="38"/>
                    <line x1="16" y1="49" x2="84" y2="49"/>
                    <line x1="16" y1="60" x2="84" y2="60"/>
                    <line x1="16" y1="71" x2="84" y2="71"/>
                    <line x1="16" y1="82" x2="62" y2="82"/>
                </g>

                <!-- Realistic Hex Pencil Lying Across -->
                <g filter="url(#nx-notes-shadow)" transform="rotate(-32 60 70)">
                    <!-- Pencil Body -->
                    <rect x="36" y="66" width="38" height="6.5" rx="1" fill="#facc15"/>
                    <!-- Metal Ferrule -->
                    <rect x="74" y="66" width="6" height="6.5" fill="#94a3b8"/>
                    <!-- Pink Eraser -->
                    <rect x="80" y="66" width="6" height="6.5" rx="1.5" fill="#f43f5e"/>
                    <!-- Wood Tip -->
                    <polygon points="36,66 36,72.5 28,69.2" fill="#fed7aa"/>
                    <!-- Graphite Point -->
                    <polygon points="30,67.8 30,70.8 28,69.2" fill="#1e293b"/>
                </g>
            </svg>
        `,

        // 6. DOCS / NEXUS DOCS (Folha de documento timbrada com dobra 3D e caneta tinteiro)
        docs: `
            <svg viewBox="0 0 100 100" class="w-full h-full select-none" xmlns="http://www.w3.org/2000/svg">
                <defs>
                    <linearGradient id="nx-docs-bg" x1="0%" y1="0%" x2="0%" y2="100%">
                        <stop offset="0%" stop-color="#ff9f0a"/>
                        <stop offset="100%" stop-color="#ea580c"/>
                    </linearGradient>
                    <linearGradient id="nx-paper-grad" x1="0%" y1="0%" x2="100%" y2="100%">
                        <stop offset="0%" stop-color="#ffffff"/>
                        <stop offset="100%" stop-color="#f1f5f9"/>
                    </linearGradient>
                    <filter id="nx-paper-shadow">
                        <feDropShadow dx="0" dy="3" stdDeviation="2" flood-color="#7c2d12" flood-opacity="0.45"/>
                    </filter>
                </defs>
                <rect x="4" y="4" width="92" height="92" rx="22" fill="url(#nx-docs-bg)"/>
                <rect x="4.5" y="4.5" width="91" height="91" rx="21.5" fill="none" stroke="rgba(255,255,255,0.4)" stroke-width="1.2"/>

                <!-- Paper Sheet with Folded Corner -->
                <g filter="url(#nx-paper-shadow)">
                    <path d="M 22 18 L 62 18 L 78 34 L 78 82 C 78 84, 76 86, 74 86 L 26 86 C 24 86, 22 84, 22 82 Z" fill="url(#nx-paper-grad)"/>
                    <!-- Folded Corner Flap -->
                    <path d="M 62 18 L 78 34 L 64 34 C 63 34, 62 33, 62 32 Z" fill="#cbd5e1"/>
                    <path d="M 62 18 L 78 34 L 62 34 Z" fill="none" stroke="#94a3b8" stroke-width="0.8"/>

                    <!-- Text Paragraph Lines -->
                    <g fill="#94a3b8" opacity="0.85">
                        <rect x="30" y="32" width="24" height="3" rx="1.5" fill="#ea580c"/>
                        <rect x="30" y="42" width="38" height="2.5" rx="1"/>
                        <rect x="30" y="49" width="38" height="2.5" rx="1"/>
                        <rect x="30" y="56" width="34" height="2.5" rx="1"/>
                        <rect x="30" y="63" width="38" height="2.5" rx="1"/>
                        <rect x="30" y="70" width="22" height="2.5" rx="1"/>
                    </g>
                    <!-- Golden Seal Stamp -->
                    <circle cx="65" cy="72" r="5.5" fill="#f59e0b" stroke="#d97706" stroke-width="0.8"/>
                </g>
            </svg>
        `,

        // 7. CALCULATOR (Calculadora autêntica com display LCD e botões circulares)
        calculator: `
            <svg viewBox="0 0 100 100" class="w-full h-full select-none" xmlns="http://www.w3.org/2000/svg">
                <defs>
                    <linearGradient id="nx-calc-bg" x1="0%" y1="0%" x2="0%" y2="100%">
                        <stop offset="0%" stop-color="#2c2c2e"/>
                        <stop offset="100%" stop-color="#141416"/>
                    </linearGradient>
                    <linearGradient id="nx-calc-orange" x1="0%" y1="0%" x2="0%" y2="100%">
                        <stop offset="0%" stop-color="#ff9f0a"/>
                        <stop offset="100%" stop-color="#f07800"/>
                    </linearGradient>
                </defs>
                <rect x="4" y="4" width="92" height="92" rx="22" fill="url(#nx-calc-bg)"/>
                <rect x="4.5" y="4.5" width="91" height="91" rx="21.5" fill="none" stroke="rgba(255,255,255,0.2)" stroke-width="1.2"/>

                <!-- LCD Display Window -->
                <rect x="15" y="14" width="70" height="18" rx="6" fill="#000000" stroke="rgba(255,255,255,0.12)" stroke-width="1"/>
                <text x="80" y="28" font-family="-apple-system, system-ui, sans-serif" font-weight="600" font-size="12" fill="#ffffff" text-anchor="end">1,337</text>

                <!-- Keypad Grid (Realistic Round Apple Keys) -->
                <!-- Row 1 -->
                <circle cx="24" cy="42" r="7.5" fill="#505054"/>
                <text x="24" y="45.5" font-family="sans-serif" font-size="8" font-weight="700" fill="#fff" text-anchor="middle">C</text>
                <circle cx="41" cy="42" r="7.5" fill="#505054"/>
                <text x="41" y="45" font-family="sans-serif" font-size="7" font-weight="700" fill="#fff" text-anchor="middle">±</text>
                <circle cx="58" cy="42" r="7.5" fill="#505054"/>
                <text x="58" y="45" font-family="sans-serif" font-size="8" font-weight="700" fill="#fff" text-anchor="middle">%</text>
                <circle cx="75" cy="42" r="7.5" fill="url(#nx-calc-orange)"/>
                <text x="75" y="45.5" font-family="sans-serif" font-size="10" font-weight="700" fill="#fff" text-anchor="middle">÷</text>

                <!-- Row 2 -->
                <circle cx="24" cy="59" r="7.5" fill="#3a3a3c"/>
                <text x="24" y="62" font-family="sans-serif" font-size="8" font-weight="600" fill="#fff" text-anchor="middle">7</text>
                <circle cx="41" cy="59" r="7.5" fill="#3a3a3c"/>
                <text x="41" y="62" font-family="sans-serif" font-size="8" font-weight="600" fill="#fff" text-anchor="middle">8</text>
                <circle cx="58" cy="59" r="7.5" fill="#3a3a3c"/>
                <text x="58" y="62" font-family="sans-serif" font-size="8" font-weight="600" fill="#fff" text-anchor="middle">9</text>
                <circle cx="75" cy="59" r="7.5" fill="url(#nx-calc-orange)"/>
                <text x="75" y="62.5" font-family="sans-serif" font-size="9" font-weight="700" fill="#fff" text-anchor="middle">×</text>

                <!-- Row 3 -->
                <circle cx="24" cy="76" r="7.5" fill="#3a3a3c"/>
                <text x="24" y="79" font-family="sans-serif" font-size="8" font-weight="600" fill="#fff" text-anchor="middle">4</text>
                <circle cx="41" cy="76" r="7.5" fill="#3a3a3c"/>
                <text x="41" y="79" font-family="sans-serif" font-size="8" font-weight="600" fill="#fff" text-anchor="middle">5</text>
                <circle cx="58" cy="76" r="7.5" fill="#3a3a3c"/>
                <text x="58" y="79" font-family="sans-serif" font-size="8" font-weight="600" fill="#fff" text-anchor="middle">6</text>
                <circle cx="75" cy="76" r="7.5" fill="url(#nx-calc-orange)"/>
                <text x="75" y="79.5" font-family="sans-serif" font-size="10" font-weight="700" fill="#fff" text-anchor="middle">−</text>
            </svg>
        `,

        // 8. STOCKS / BAWSAQ (Apple Stocks com curva neon em alta e vela de mercado)
        stocks: `
            <svg viewBox="0 0 100 100" class="w-full h-full select-none" xmlns="http://www.w3.org/2000/svg">
                <defs>
                    <linearGradient id="nx-stocks-bg" x1="0%" y1="0%" x2="0%" y2="100%">
                        <stop offset="0%" stop-color="#141416"/>
                        <stop offset="100%" stop-color="#021c13"/>
                    </linearGradient>
                    <linearGradient id="nx-stocks-chart-fill" x1="0%" y1="0%" x2="0%" y2="100%">
                        <stop offset="0%" stop-color="#34c759" stop-opacity="0.45"/>
                        <stop offset="100%" stop-color="#34c759" stop-opacity="0.0"/>
                    </linearGradient>
                    <filter id="nx-stocks-glow">
                        <feDropShadow dx="0" dy="0" stdDeviation="2.5" flood-color="#34c759" flood-opacity="0.8"/>
                    </filter>
                </defs>
                <rect x="4" y="4" width="92" height="92" rx="22" fill="url(#nx-stocks-bg)"/>
                <rect x="4.5" y="4.5" width="91" height="91" rx="21.5" fill="none" stroke="rgba(52, 199, 89, 0.3)" stroke-width="1.2"/>

                <!-- Subtle Grid lines -->
                <g stroke="rgba(255,255,255,0.06)" stroke-width="1">
                    <line x1="12" y1="30" x2="88" y2="30"/>
                    <line x1="12" y1="50" x2="88" y2="50"/>
                    <line x1="12" y1="70" x2="88" y2="70"/>
                </g>

                <!-- Candlestick Graphic Silhouette -->
                <g fill="#34c759" opacity="0.3">
                    <rect x="22" y="52" width="5" height="14" rx="1"/>
                    <line x1="24.5" y1="48" x2="24.5" y2="69" stroke="#34c759" stroke-width="1"/>
                    <rect x="42" y="40" width="5" height="18" rx="1"/>
                    <line x1="44.5" y1="34" x2="44.5" y2="62" stroke="#34c759" stroke-width="1"/>
                    <rect x="62" y="26" width="5" height="22" rx="1"/>
                    <line x1="64.5" y1="20" x2="64.5" y2="52" stroke="#34c759" stroke-width="1"/>
                </g>

                <!-- Green Glowing Area Fill Under Curve -->
                <path d="M 12 72 Q 28 68, 40 50 T 68 42 T 88 20 L 88 84 L 12 84 Z" fill="url(#nx-stocks-chart-fill)"/>

                <!-- Main Rising Neon Trendline -->
                <path d="M 12 72 Q 28 68, 40 50 T 68 42 T 88 20" fill="none" stroke="#34c759" stroke-width="3.8" stroke-linecap="round" filter="url(#nx-stocks-glow)"/>

                <!-- Pulse Vertex at Peak -->
                <circle cx="88" cy="20" r="4.5" fill="#ffffff" filter="url(#nx-stocks-glow)"/>
                <circle cx="88" cy="20" r="2.2" fill="#34c759"/>
            </svg>
        `,

        // 9. JOBS HUB / LS CAREERS (Pasta executiva de couro legítimo com fivelas douradas)
        jobs_hub: `
            <svg viewBox="0 0 100 100" class="w-full h-full select-none" xmlns="http://www.w3.org/2000/svg">
                <defs>
                    <linearGradient id="nx-jobs-bg" x1="0%" y1="0%" x2="0%" y2="100%">
                        <stop offset="0%" stop-color="#0284c7"/>
                        <stop offset="100%" stop-color="#034694"/>
                    </linearGradient>
                    <linearGradient id="nx-leather" x1="0%" y1="0%" x2="0%" y2="100%">
                        <stop offset="0%" stop-color="#854d0e"/>
                        <stop offset="100%" stop-color="#451a03"/>
                    </linearGradient>
                    <linearGradient id="nx-gold-brass" x1="0%" y1="0%" x2="100%" y2="100%">
                        <stop offset="0%" stop-color="#fef08a"/>
                        <stop offset="50%" stop-color="#ca8a04"/>
                        <stop offset="100%" stop-color="#854d0e"/>
                    </linearGradient>
                    <filter id="nx-briefcase-shadow">
                        <feDropShadow dx="0" dy="3" stdDeviation="2" flood-color="#02204a" flood-opacity="0.5"/>
                    </filter>
                </defs>
                <rect x="4" y="4" width="92" height="92" rx="22" fill="url(#nx-jobs-bg)"/>
                <rect x="4.5" y="4.5" width="91" height="91" rx="21.5" fill="none" stroke="rgba(255,255,255,0.3)" stroke-width="1.2"/>

                <!-- Briefcase Body -->
                <g filter="url(#nx-briefcase-shadow)">
                    <!-- Handle -->
                    <path d="M 40 26 C 40 20, 60 20, 60 26" fill="none" stroke="url(#nx-leather)" stroke-width="5" stroke-linecap="round"/>
                    <rect x="38" y="24" width="5" height="4" rx="1" fill="url(#nx-gold-brass)"/>
                    <rect x="57" y="24" width="5" height="4" rx="1" fill="url(#nx-gold-brass)"/>

                    <!-- Main Bag Case -->
                    <rect x="18" y="28" width="64" height="48" rx="8" fill="url(#nx-leather)"/>
                    <!-- Leather Flap Upper Cover -->
                    <path d="M 18 28 L 82 28 C 82 28, 82 50, 82 50 L 58 56 C 52 57, 48 57, 42 56 L 18 50 Z" fill="#713f12"/>
                    <path d="M 18 28 L 82 28 C 82 28, 82 50, 82 50 L 58 56 C 52 57, 48 57, 42 56 L 18 50 Z" fill="none" stroke="rgba(255,255,255,0.2)" stroke-width="0.8"/>

                    <!-- Brass Buckle Latches -->
                    <rect x="30" y="46" width="7" height="12" rx="1.5" fill="url(#nx-gold-brass)"/>
                    <rect x="63" y="46" width="7" height="12" rx="1.5" fill="url(#nx-gold-brass)"/>
                    <!-- Keyhole slot in buckle -->
                    <circle cx="33.5" cy="52" r="1" fill="#451a03"/>
                    <circle cx="66.5" cy="52" r="1" fill="#451a03"/>
                    <!-- Corner Brass Protectors -->
                    <path d="M 18 68 L 26 76 L 18 76 Z" fill="url(#nx-gold-brass)"/>
                    <path d="M 82 68 L 74 76 L 82 76 Z" fill="url(#nx-gold-brass)"/>
                </g>
            </svg>
        `,

        // 10. TERMINAL (Console CRT fosco com prompt phosphor verde e LEDs)
        terminal: `
            <svg viewBox="0 0 100 100" class="w-full h-full select-none" xmlns="http://www.w3.org/2000/svg">
                <defs>
                    <linearGradient id="nx-term-bg" x1="0%" y1="0%" x2="0%" y2="100%">
                        <stop offset="0%" stop-color="#1f1f23"/>
                        <stop offset="100%" stop-color="#0a0a0c"/>
                    </linearGradient>
                    <filter id="nx-term-glow">
                        <feDropShadow dx="0" dy="0" stdDeviation="2" flood-color="#32d74b" flood-opacity="0.8"/>
                    </filter>
                </defs>
                <rect x="4" y="4" width="92" height="92" rx="22" fill="url(#nx-term-bg)"/>
                <rect x="4.5" y="4.5" width="91" height="91" rx="21.5" fill="none" stroke="rgba(50, 215, 75, 0.45)" stroke-width="1.2"/>

                <!-- Header Bar -->
                <rect x="8" y="8" width="84" height="15" rx="5" fill="#141416"/>
                <!-- Mini Traffic Lights on Header -->
                <circle cx="16" cy="15.5" r="2.2" fill="#ff5f57"/>
                <circle cx="23" cy="15.5" r="2.2" fill="#febc2e"/>
                <circle cx="30" cy="15.5" r="2.2" fill="#28c840"/>

                <!-- CRT Screen Body with Scanlines -->
                <rect x="8" y="22" width="84" height="70" rx="3" fill="#040804"/>

                <!-- Phosphor Green CLI Prompt -->
                <g filter="url(#nx-term-glow)">
                    <text x="14" y="46" font-family="'JetBrains Mono', monospace" font-size="17" font-weight="800" fill="#32d74b">&gt;_</text>
                    <!-- Blinking Cursor Block -->
                    <rect x="36" y="34" width="9" height="13" rx="1" fill="#32d74b"/>
                </g>
                <!-- Terminal Command Snippet -->
                <text x="14" y="65" font-family="'JetBrains Mono', monospace" font-size="6.5" font-weight="600" fill="#4ade80" opacity="0.6">root@nexus:~$ bypass</text>
                <text x="14" y="76" font-family="'JetBrains Mono', monospace" font-size="6.5" font-weight="600" fill="#22c55e" opacity="0.35">[OK] port 22 open</text>
            </svg>
        `,

        // 10B. ONLINE BANKING / MAZE BANK & FLEECA (Portal bancário com colunas clássicas e cartão de crédito)
        online_banking: `
            <svg viewBox="0 0 100 100" class="w-full h-full select-none" xmlns="http://www.w3.org/2000/svg">
                <defs>
                    <linearGradient id="nx-bank-bg" x1="0%" y1="0%" x2="0%" y2="100%">
                        <stop offset="0%" stop-color="#991b1b"/>
                        <stop offset="50%" stop-color="#7f1d1d"/>
                        <stop offset="100%" stop-color="#450a0a"/>
                    </linearGradient>
                    <linearGradient id="nx-bank-gold" x1="0%" y1="0%" x2="100%" y2="100%">
                        <stop offset="0%" stop-color="#fef08a"/>
                        <stop offset="50%" stop-color="#eab308"/>
                        <stop offset="100%" stop-color="#ca8a04"/>
                    </linearGradient>
                    <linearGradient id="nx-bank-glass" x1="0%" y1="0%" x2="0%" y2="100%">
                        <stop offset="0%" stop-color="#ffffff" stop-opacity="0.35"/>
                        <stop offset="35%" stop-color="#ffffff" stop-opacity="0.05"/>
                        <stop offset="100%" stop-color="#ffffff" stop-opacity="0"/>
                    </linearGradient>
                    <filter id="nx-bank-shadow">
                        <feDropShadow dx="0" dy="3" stdDeviation="2.5" flood-color="#000000" flood-opacity="0.6"/>
                    </filter>
                </defs>
                <rect x="4" y="4" width="92" height="92" rx="22" fill="url(#nx-bank-bg)"/>
                <rect x="5" y="5" width="90" height="42" rx="21" fill="url(#nx-bank-glass)"/>
                <rect x="4.5" y="4.5" width="91" height="91" rx="21.5" fill="none" stroke="rgba(250, 204, 21, 0.4)" stroke-width="1.2"/>

                <!-- Bank Icon Graphical Core -->
                <g filter="url(#nx-bank-shadow)" fill="url(#nx-bank-gold)">
                    <!-- Pediment (Triângulo Superior) -->
                    <polygon points="50,22 24,35 76,35"/>
                    <rect x="22" y="35" width="56" height="4" rx="1.5"/>

                    <!-- Colunas Neoclássicas (4 Colunas) -->
                    <rect x="26" y="41" width="8" height="26" rx="2"/>
                    <rect x="38" y="41" width="8" height="26" rx="2"/>
                    <rect x="54" y="41" width="8" height="26" rx="2"/>
                    <rect x="66" y="41" width="8" height="26" rx="2"/>

                    <!-- Base / Escadaria -->
                    <rect x="20" y="69" width="60" height="4" rx="1.5"/>
                    <rect x="16" y="74" width="68" height="5" rx="2"/>

                    <!-- Símbolo de Moeda / Emblema Central -->
                    <circle cx="50" cy="29" r="3" fill="#ffffff" opacity="0.9"/>
                </g>
            </svg>
        `,

        // 11. CRYPTO / NEXUS CRYPTO (Moeda física dourada em relevo com pistas de circuito)
        crypto: `
            <svg viewBox="0 0 100 100" class="w-full h-full select-none" xmlns="http://www.w3.org/2000/svg">
                <defs>
                    <linearGradient id="nx-crypto-bg" x1="0%" y1="0%" x2="0%" y2="100%">
                        <stop offset="0%" stop-color="#14532d"/>
                        <stop offset="100%" stop-color="#022c15"/>
                    </linearGradient>
                    <radialGradient id="nx-coin-gold" cx="40%" cy="35%" r="65%">
                        <stop offset="0%" stop-color="#fffbeb"/>
                        <stop offset="35%" stop-color="#fde047"/>
                        <stop offset="70%" stop-color="#ca8a04"/>
                        <stop offset="100%" stop-color="#713f12"/>
                    </radialGradient>
                    <filter id="nx-coin-shadow">
                        <feDropShadow dx="0" dy="4" stdDeviation="3" flood-color="#000000" flood-opacity="0.55"/>
                    </filter>
                </defs>
                <rect x="4" y="4" width="92" height="92" rx="22" fill="url(#nx-crypto-bg)"/>
                <rect x="4.5" y="4.5" width="91" height="91" rx="21.5" fill="none" stroke="rgba(250, 204, 21, 0.4)" stroke-width="1.2"/>

                <!-- Minted Physical Coin 3D -->
                <g filter="url(#nx-coin-shadow)">
                    <!-- Outer Coin Rim with Ridges -->
                    <circle cx="50" cy="50" r="36" fill="url(#nx-coin-gold)"/>
                    <circle cx="50" cy="50" r="32" fill="#a16207"/>
                    <circle cx="50" cy="50" r="30" fill="url(#nx-coin-gold)"/>

                    <!-- Circuit Board Traces on Coin Surface -->
                    <g stroke="#854d0e" stroke-width="1.2" opacity="0.6" stroke-linecap="round">
                        <line x1="28" y1="36" x2="38" y2="36"/>
                        <circle cx="28" cy="36" r="1.5" fill="#854d0e"/>
                        <line x1="62" y1="64" x2="72" y2="64"/>
                        <circle cx="72" cy="64" r="1.5" fill="#854d0e"/>
                    </g>

                    <!-- Embossed Crypto Symbol 'Q' / '₿' -->
                    <text x="50" y="58" font-family="-apple-system, sans-serif" font-size="26" font-weight="900" fill="#78350f" text-anchor="middle" opacity="0.85">₿</text>
                    <text x="49" y="57" font-family="-apple-system, sans-serif" font-size="26" font-weight="900" fill="#fef08a" text-anchor="middle">₿</text>
                </g>
            </svg>
        `,

        // 12. DARKWEB / THE SILK ROAD (Cebola criptográfica Tor / fechadura cyberpunk neon)
        darkweb: `
            <svg viewBox="0 0 100 100" class="w-full h-full select-none" xmlns="http://www.w3.org/2000/svg">
                <defs>
                    <linearGradient id="nx-dark-bg" x1="0%" y1="0%" x2="0%" y2="100%">
                        <stop offset="0%" stop-color="#2e0854"/>
                        <stop offset="100%" stop-color="#090114"/>
                    </linearGradient>
                    <linearGradient id="nx-dark-neon" x1="0%" y1="0%" x2="100%" y2="100%">
                        <stop offset="0%" stop-color="#e879f9"/>
                        <stop offset="100%" stop-color="#a855f7"/>
                    </linearGradient>
                    <filter id="nx-dark-glow">
                        <feDropShadow dx="0" dy="0" stdDeviation="3" flood-color="#c084fc" flood-opacity="0.75"/>
                    </filter>
                </defs>
                <rect x="4" y="4" width="92" height="92" rx="22" fill="url(#nx-dark-bg)"/>
                <rect x="4.5" y="4.5" width="91" height="91" rx="21.5" fill="none" stroke="rgba(192, 132, 252, 0.45)" stroke-width="1.2"/>

                <!-- Cyber Matrix Grid -->
                <circle cx="50" cy="50" r="36" fill="none" stroke="rgba(168, 85, 247, 0.15)" stroke-width="1" stroke-dasharray="3 3"/>
                <circle cx="50" cy="50" r="26" fill="none" stroke="rgba(168, 85, 247, 0.25)" stroke-width="1"/>

                <!-- Neon Onion / Anonymous Keyhole Icon -->
                <g filter="url(#nx-dark-glow)">
                    <!-- Outer Onion Layers -->
                    <path d="M 50 20 C 30 35, 24 55, 34 72 C 40 80, 60 80, 66 72 C 76 55, 70 35, 50 20 Z" fill="none" stroke="url(#nx-dark-neon)" stroke-width="2.5" stroke-linejoin="round"/>
                    <path d="M 50 30 C 38 42, 34 56, 40 68 C 45 74, 55 74, 60 68 C 66 56, 62 42, 50 30 Z" fill="none" stroke="#f0abfc" stroke-width="2"/>
                    <!-- Core Keyhole -->
                    <circle cx="50" cy="50" r="4.5" fill="#fdf4ff"/>
                    <polygon points="48,52 52,52 54,63 46,63" fill="#fdf4ff"/>
                </g>
            </svg>
        `,

        // 13. BOOSTING / BENNYS (Tacômetro esportivo com agulha na faixa vermelha)
        boosting: `
            <svg viewBox="0 0 100 100" class="w-full h-full select-none" xmlns="http://www.w3.org/2000/svg">
                <defs>
                    <linearGradient id="nx-boost-bg" x1="0%" y1="0%" x2="0%" y2="100%">
                        <stop offset="0%" stop-color="#3f0f0c"/>
                        <stop offset="100%" stop-color="#120403"/>
                    </linearGradient>
                    <filter id="nx-needle-glow">
                        <feDropShadow dx="0" dy="0" stdDeviation="2.5" flood-color="#ef4444" flood-opacity="0.9"/>
                    </filter>
                </defs>
                <rect x="4" y="4" width="92" height="92" rx="22" fill="url(#nx-boost-bg)"/>
                <rect x="4.5" y="4.5" width="91" height="91" rx="21.5" fill="none" stroke="rgba(239, 68, 68, 0.4)" stroke-width="1.2"/>

                <!-- Gauge Face Rim -->
                <circle cx="50" cy="50" r="36" fill="#050505" stroke="#262626" stroke-width="2"/>

                <!-- Speedometer Arc (Normal Zone: White) -->
                <path d="M 22 66 A 32 32 0 1 1 66 22" fill="none" stroke="#52525b" stroke-width="3" stroke-linecap="round"/>
                <!-- Redline Zone (High RPM: Red) -->
                <path d="M 66 22 A 32 32 0 0 1 78 66" fill="none" stroke="#ef4444" stroke-width="4.5" stroke-linecap="round"/>

                <!-- RPM Ticks -->
                <g stroke="#ffffff" stroke-width="1.5" stroke-linecap="round" opacity="0.8">
                    <line x1="26" y1="62" x2="30" y2="58"/>
                    <line x1="22" y1="46" x2="27" y2="46"/>
                    <line x1="30" y1="30" x2="34" y2="34"/>
                    <line x1="50" y1="20" x2="50" y2="26"/>
                    <line x1="70" y1="30" x2="66" y2="34" stroke="#ef4444"/>
                    <line x1="74" y1="62" x2="70" y2="58" stroke="#ef4444"/>
                </g>

                <text x="50" y="65" font-family="'JetBrains Mono', monospace" font-size="7" font-weight="700" fill="#94a3b8" text-anchor="middle">RPM x1000</text>

                <!-- High-RPM Glowing Red Needle -->
                <g filter="url(#nx-needle-glow)">
                    <line x1="50" y1="50" x2="72" y2="30" stroke="#ef4444" stroke-width="3" stroke-linecap="round"/>
                    <circle cx="50" cy="50" r="5" fill="#ffffff"/>
                    <circle cx="50" cy="50" r="2.5" fill="#ef4444"/>
                </g>
            </svg>
        `,

        // 14. 3D PRINTER / PRINTFORGE STUDIO (Bico extrusor com cubo holográfico 3D)
        ifruit_workshop: `
            <svg viewBox="0 0 100 100" class="w-full h-full select-none" xmlns="http://www.w3.org/2000/svg">
                <defs>
                    <linearGradient id="nx-print-bg" x1="0%" y1="0%" x2="0%" y2="100%">
                        <stop offset="0%" stop-color="#0284c7"/>
                        <stop offset="100%" stop-color="#082f49"/>
                    </linearGradient>
                    <filter id="nx-holo-glow">
                        <feDropShadow dx="0" dy="0" stdDeviation="3" flood-color="#38bdf8" flood-opacity="0.85"/>
                    </filter>
                </defs>
                <rect x="4" y="4" width="92" height="92" rx="22" fill="url(#nx-print-bg)"/>
                <rect x="4.5" y="4.5" width="91" height="91" rx="21.5" fill="none" stroke="rgba(56, 189, 248, 0.4)" stroke-width="1.2"/>

                <!-- 3D Printer Extruder Head -->
                <rect x="38" y="16" width="24" height="10" rx="2" fill="#64748b"/>
                <rect x="44" y="26" width="12" height="6" fill="#f59e0b"/>
                <!-- Brass Nozzle -->
                <polygon points="46,32 54,32 50,38" fill="#d97706"/>
                <!-- Laser Guide Beam -->
                <line x1="50" y1="38" x2="50" y2="48" stroke="#38bdf8" stroke-width="1" stroke-dasharray="1 2"/>

                <!-- Holographic Isometric 3D Wireframe Cube -->
                <g filter="url(#nx-holo-glow)" stroke="#38bdf8" stroke-width="2" stroke-linejoin="round" fill="none">
                    <!-- Top Face -->
                    <polygon points="50,48 68,58 50,68 32,58" fill="rgba(56, 189, 248, 0.25)"/>
                    <!-- Left Face -->
                    <polygon points="32,58 50,68 50,86 32,76" fill="rgba(14, 165, 233, 0.4)"/>
                    <!-- Right Face -->
                    <polygon points="50,68 68,58 68,76 50,86" fill="rgba(2, 132, 199, 0.55)"/>
                </g>
            </svg>
        `,

        // 15. CARDFORGE & MSR (Cartão de crédito preto com chip EMV dourado e tarja)
        card_forge: `
            <svg viewBox="0 0 100 100" class="w-full h-full select-none" xmlns="http://www.w3.org/2000/svg">
                <defs>
                    <linearGradient id="nx-card-bg" x1="0%" y1="0%" x2="0%" y2="100%">
                        <stop offset="0%" stop-color="#334155"/>
                        <stop offset="100%" stop-color="#0f172a"/>
                    </linearGradient>
                    <linearGradient id="nx-chip-gold" x1="0%" y1="0%" x2="100%" y2="100%">
                        <stop offset="0%" stop-color="#fef08a"/>
                        <stop offset="100%" stop-color="#ca8a04"/>
                    </linearGradient>
                    <filter id="nx-card-shadow">
                        <feDropShadow dx="0" dy="4" stdDeviation="3" flood-color="#000000" flood-opacity="0.6"/>
                    </filter>
                </defs>
                <rect x="4" y="4" width="92" height="92" rx="22" fill="url(#nx-card-bg)"/>
                <rect x="4.5" y="4.5" width="91" height="91" rx="21.5" fill="none" stroke="rgba(255,255,255,0.2)" stroke-width="1.2"/>

                <!-- Titanium Credit Card Body -->
                <g filter="url(#nx-card-shadow)">
                    <rect x="14" y="24" width="72" height="48" rx="6" fill="#18181b" stroke="rgba(255,255,255,0.3)" stroke-width="1"/>

                    <!-- EMV Gold Microchip -->
                    <rect x="22" y="36" width="14" height="11" rx="2" fill="url(#nx-chip-gold)"/>
                    <g stroke="#78350f" stroke-width="0.8">
                        <line x1="22" y1="41.5" x2="36" y2="41.5"/>
                        <line x1="29" y1="36" x2="29" y2="47"/>
                    </g>

                    <!-- Contactless Wireless Waves -->
                    <path d="M 42 38 A 4 4 0 0 1 42 45" fill="none" stroke="#94a3b8" stroke-width="1.2" stroke-linecap="round"/>
                    <path d="M 45 36 A 7 7 0 0 1 45 47" fill="none" stroke="#94a3b8" stroke-width="1.2" stroke-linecap="round"/>

                    <!-- Holographic Card Number Mockup -->
                    <text x="22" y="58" font-family="'JetBrains Mono', monospace" font-size="5.5" font-weight="700" fill="#e2e8f0" letter-spacing="1">4532 •••• •••• 8821</text>
                    <text x="22" y="65" font-family="-apple-system, sans-serif" font-size="4" font-weight="600" fill="#94a3b8">NEXUS BLACK</text>

                    <!-- Card Issuer Overlapping Circles -->
                    <circle cx="72" cy="62" r="4.5" fill="#ea580c" opacity="0.85"/>
                    <circle cx="77" cy="62" r="4.5" fill="#facc15" opacity="0.85"/>
                </g>
            </svg>
        `,

        // 16. CCTV CAMERA VIEWER (Câmera domo com lente reflexiva e LED vermelho)
        cctv_viewer: `
            <svg viewBox="0 0 100 100" class="w-full h-full select-none" xmlns="http://www.w3.org/2000/svg">
                <defs>
                    <linearGradient id="nx-cctv-bg" x1="0%" y1="0%" x2="0%" y2="100%">
                        <stop offset="0%" stop-color="#0284c7"/>
                        <stop offset="100%" stop-color="#0c4a6e"/>
                    </linearGradient>
                    <filter id="nx-cctv-red">
                        <feDropShadow dx="0" dy="0" stdDeviation="2.5" flood-color="#ef4444" flood-opacity="0.9"/>
                    </filter>
                </defs>
                <rect x="4" y="4" width="92" height="92" rx="22" fill="url(#nx-cctv-bg)"/>
                <rect x="4.5" y="4.5" width="91" height="91" rx="21.5" fill="none" stroke="rgba(255,255,255,0.3)" stroke-width="1.2"/>

                <!-- Ceiling Mount Base -->
                <ellipse cx="50" cy="30" rx="32" ry="8" fill="#334155" stroke="#64748b" stroke-width="1.5"/>

                <!-- Smoked Glass Dome -->
                <path d="M 22 30 C 22 58, 78 58, 78 30 Z" fill="#0f172a" stroke="#475569" stroke-width="1"/>
                <!-- Specular Curved Highlight on Dome -->
                <path d="M 28 32 C 30 50, 70 50, 72 32" fill="none" stroke="rgba(255,255,255,0.4)" stroke-width="1.8"/>

                <!-- Internal Camera Lens Eye -->
                <circle cx="50" cy="42" r="9" fill="#020617"/>
                <circle cx="50" cy="42" r="6" fill="#0284c7"/>
                <circle cx="50" cy="42" r="3" fill="#000000"/>
                <circle cx="48" cy="40" r="1.5" fill="#ffffff"/>

                <!-- Blinking Red Recording LED -->
                <circle cx="68" cy="38" r="2.5" fill="#ef4444" filter="url(#nx-cctv-red)"/>
            </svg>
        `,

        // 17. POLICE MDT (Distintivo estelar dourado oficial com escudo e fita azul)
        police_mdt: `
            <svg viewBox="0 0 100 100" class="w-full h-full select-none" xmlns="http://www.w3.org/2000/svg">
                <defs>
                    <linearGradient id="nx-police-bg" x1="0%" y1="0%" x2="0%" y2="100%">
                        <stop offset="0%" stop-color="#1e3a8a"/>
                        <stop offset="100%" stop-color="#0f172a"/>
                    </linearGradient>
                    <linearGradient id="nx-badge-gold" x1="0%" y1="0%" x2="100%" y2="100%">
                        <stop offset="0%" stop-color="#fef08a"/>
                        <stop offset="50%" stop-color="#eab308"/>
                        <stop offset="100%" stop-color="#854d0e"/>
                    </linearGradient>
                    <filter id="nx-badge-shadow">
                        <feDropShadow dx="0" dy="3" stdDeviation="2.5" flood-color="#000000" flood-opacity="0.5"/>
                    </filter>
                </defs>
                <rect x="4" y="4" width="92" height="92" rx="22" fill="url(#nx-police-bg)"/>
                <rect x="4.5" y="4.5" width="91" height="91" rx="21.5" fill="none" stroke="rgba(234, 179, 8, 0.4)" stroke-width="1.2"/>

                <!-- LSPD Official Shield / Star Badge -->
                <g filter="url(#nx-badge-shadow)">
                    <!-- 7-Point Star Points -->
                    <polygon points="50,16 57,28 71,24 72,39 85,45 77,57 84,69 70,72 68,86 54,82 50,90 46,82 32,86 30,72 16,69 23,57 15,45 28,39 29,24 43,28" fill="url(#nx-badge-gold)"/>

                    <!-- Center Medallion Shield -->
                    <circle cx="50" cy="53" r="16" fill="#1e3a8a" stroke="#ca8a04" stroke-width="1.5"/>
                    <text x="50" y="50" font-family="-apple-system, sans-serif" font-size="6.5" font-weight="900" fill="#fef08a" text-anchor="middle">LSPD</text>
                    <text x="50" y="58" font-family="-apple-system, sans-serif" font-size="4.5" font-weight="700" fill="#ffffff" text-anchor="middle">OFFICER</text>
                </g>
            </svg>
        `,

        // 17.5. CSI FORENSICS (Impressão digital pericial com scanner laser e lente de análise)
        crimescene: `
            <svg viewBox="0 0 100 100" class="w-full h-full select-none" xmlns="http://www.w3.org/2000/svg">
                <defs>
                    <linearGradient id="nx-csi-bg" x1="0%" y1="0%" x2="0%" y2="100%">
                        <stop offset="0%" stop-color="#0284c7"/>
                        <stop offset="100%" stop-color="#082f49"/>
                    </linearGradient>
                    <linearGradient id="nx-csi-laser" x1="0%" y1="0%" x2="100%" y2="0%">
                        <stop offset="0%" stop-color="#38bdf8" stop-opacity="0"/>
                        <stop offset="50%" stop-color="#38bdf8" stop-opacity="0.8"/>
                        <stop offset="100%" stop-color="#38bdf8" stop-opacity="0"/>
                    </linearGradient>
                </defs>
                <rect x="4" y="4" width="92" height="92" rx="22" fill="url(#nx-csi-bg)"/>
                <rect x="4.5" y="4.5" width="91" height="91" rx="21.5" fill="none" stroke="rgba(56, 189, 248, 0.4)" stroke-width="1.2"/>

                <g fill="none" stroke="#7dd3fc" stroke-width="2.5" stroke-linecap="round" opacity="0.9">
                    <path d="M 50 25 A 22 26 0 0 0 32 46 C 31 56 34 68 38 78"/>
                    <path d="M 50 31 A 16 19 0 0 0 38 48 C 37 57 40 68 44 76"/>
                    <path d="M 50 37 A 10 12 0 0 0 43 49 C 42 58 45 66 48 74"/>
                    <path d="M 50 43 A 5 6 0 0 0 47 49 C 47 55 49 61 51 68"/>
                    <path d="M 50 25 A 22 26 0 0 1 68 46 C 69 56 66 68 62 78"/>
                    <path d="M 50 31 A 16 19 0 0 1 62 48 C 63 57 60 68 56 76"/>
                    <path d="M 50 37 A 10 12 0 0 1 57 49 C 58 58 55 66 52 74"/>
                </g>

                <line x1="12" y1="52" x2="88" y2="52" stroke="url(#nx-csi-laser)" stroke-width="3"/>
                <circle cx="50" cy="52" r="2.5" fill="#38bdf8"/>

                <rect x="28" y="74" width="44" height="12" rx="3" fill="#0f172a" stroke="#0284c7" stroke-width="1"/>
                <text x="50" y="82.5" font-family="-apple-system, sans-serif" font-size="6.5" font-weight="900" fill="#38bdf8" text-anchor="middle">FORENSIC</text>
            </svg>
        `,

        // 18. LAUNCHPAD (Grid 3x3 de aplicativos coloridos estilo Apple Sonoma)
        launchpad: `
            <svg viewBox="0 0 100 100" class="w-full h-full select-none" xmlns="http://www.w3.org/2000/svg">
                <defs>
                    <linearGradient id="nx-launch-bg" x1="0%" y1="0%" x2="0%" y2="100%">
                        <stop offset="0%" stop-color="#334155"/>
                        <stop offset="100%" stop-color="#0f172a"/>
                    </linearGradient>
                </defs>
                <rect x="4" y="4" width="92" height="92" rx="22" fill="url(#nx-launch-bg)"/>
                <rect x="4.5" y="4.5" width="91" height="91" rx="21.5" fill="none" stroke="rgba(255,255,255,0.25)" stroke-width="1.2"/>

                <!-- 3x3 Grid of macOS Colorful Mini Icons -->
                <!-- Row 1 -->
                <rect x="18" y="18" width="16" height="16" rx="4.5" fill="#ef4444"/>
                <rect x="42" y="18" width="16" height="16" rx="4.5" fill="#f97316"/>
                <rect x="66" y="18" width="16" height="16" rx="4.5" fill="#eab308"/>
                <!-- Row 2 -->
                <rect x="18" y="42" width="16" height="16" rx="4.5" fill="#22c55e"/>
                <rect x="42" y="42" width="16" height="16" rx="4.5" fill="#06b6d4"/>
                <rect x="66" y="42" width="16" height="16" rx="4.5" fill="#3b82f6"/>
                <!-- Row 3 -->
                <rect x="18" y="66" width="16" height="16" rx="4.5" fill="#8b5cf6"/>
                <rect x="42" y="66" width="16" height="16" rx="4.5" fill="#ec4899"/>
                <rect x="66" y="66" width="16" height="16" rx="4.5" fill="#64748b"/>
            </svg>
        `,

        // 19. TRASH / LIXEIRA (Cesto de lixo aramado/acrílico transparente com papel)
        trash: `
            <svg viewBox="0 0 100 100" class="w-full h-full select-none" xmlns="http://www.w3.org/2000/svg">
                <defs>
                    <linearGradient id="nx-trash-metal" x1="0%" y1="0%" x2="100%" y2="0%">
                        <stop offset="0%" stop-color="#94a3b8"/>
                        <stop offset="50%" stop-color="#f8fafc"/>
                        <stop offset="100%" stop-color="#64748b"/>
                    </linearGradient>
                    <filter id="nx-trash-shadow">
                        <feDropShadow dx="0" dy="3" stdDeviation="2" flood-color="#000000" flood-opacity="0.4"/>
                    </filter>
                </defs>
                <g filter="url(#nx-trash-shadow)">
                    <!-- Wastebasket Body (Trapezoid Wire Mesh) -->
                    <path d="M 28 32 L 35 84 C 35 86, 37 88, 40 88 L 60 88 C 63 88, 65 86, 65 84 L 72 32 Z" fill="rgba(255,255,255,0.18)" stroke="url(#nx-trash-metal)" stroke-width="2"/>
                    <!-- Top Rim Oval -->
                    <ellipse cx="50" cy="30" rx="24" ry="6" fill="#475569" stroke="url(#nx-trash-metal)" stroke-width="2"/>
                    <ellipse cx="50" cy="30" rx="22" ry="4.5" fill="#1e293b"/>

                    <!-- Wire Mesh Ribs -->
                    <g stroke="rgba(255,255,255,0.3)" stroke-width="1.2">
                        <line x1="39" y1="33" x2="43" y2="86"/>
                        <line x1="50" y1="34" x2="50" y2="88"/>
                        <line x1="61" y1="33" x2="57" y2="86"/>
                        <!-- Horizontal Rings -->
                        <path d="M 31 50 Q 50 56 69 50" fill="none"/>
                        <path d="M 33 68 Q 50 74 67 68" fill="none"/>
                    </g>

                    <!-- Crumpled Paper Balls Inside -->
                    <circle cx="48" cy="40" r="7" fill="#ffffff" opacity="0.95"/>
                    <path d="M 44 38 L 47 44 L 52 38 L 54 43 Z" fill="#e2e8f0"/>
                    <circle cx="58" cy="44" r="5" fill="#f1f5f9" opacity="0.9"/>
                </g>
            </svg>
        `,

        // 20. POWER / DESLIGAR (Botão metálico escovado com anel de energia vermelho iluminado)
        power: `
            <svg viewBox="0 0 100 100" class="w-full h-full select-none" xmlns="http://www.w3.org/2000/svg">
                <defs>
                    <linearGradient id="nx-power-bg" x1="0%" y1="0%" x2="0%" y2="100%">
                        <stop offset="0%" stop-color="#b91c1c"/>
                        <stop offset="100%" stop-color="#450a0a"/>
                    </linearGradient>
                    <filter id="nx-power-glow">
                        <feDropShadow dx="0" dy="0" stdDeviation="3" flood-color="#ef4444" flood-opacity="0.9"/>
                    </filter>
                </defs>
                <rect x="4" y="4" width="92" height="92" rx="22" fill="url(#nx-power-bg)"/>
                <rect x="4.5" y="4.5" width="91" height="91" rx="21.5" fill="none" stroke="rgba(255,255,255,0.3)" stroke-width="1.2"/>

                <!-- Metallic Recessed Center -->
                <circle cx="50" cy="50" r="30" fill="#18181b" stroke="#7f1d1d" stroke-width="1.5"/>

                <!-- Illuminated Power Symbol -->
                <g filter="url(#nx-power-glow)" stroke="#ffffff" stroke-width="4.5" stroke-linecap="round">
                    <!-- Circle Arc -->
                    <path d="M 36 40 A 18 18 0 1 0 64 40" fill="none"/>
                    <!-- Vertical Line -->
                    <line x1="50" y1="28" x2="50" y2="48"/>
                </g>
            </svg>
        `,

        // 20. GASSTATION MANAGER (Bomba de combustível com gradiente âmbar)
        gas_manager: `
            <svg viewBox="0 0 100 100" class="w-full h-full select-none" xmlns="http://www.w3.org/2000/svg">
                <defs>
                    <linearGradient id="nx-gas-bg" x1="0%" y1="0%" x2="0%" y2="100%">
                        <stop offset="0%" stop-color="#f59e0b"/>
                        <stop offset="100%" stop-color="#b45309"/>
                    </linearGradient>
                </defs>
                <rect x="4" y="4" width="92" height="92" rx="22" fill="url(#nx-gas-bg)"/>
                <rect x="4.5" y="4.5" width="91" height="91" rx="21.5" fill="none" stroke="rgba(255,255,255,0.4)" stroke-width="1.2"/>
                <g fill="#ffffff">
                    <rect x="26" y="24" width="34" height="52" rx="6" fill="#1e293b"/>
                    <rect x="32" y="32" width="22" height="14" rx="2" fill="#38bdf8"/>
                    <rect x="30" y="52" width="26" height="4" rx="1" fill="#cbd5e1"/>
                    <path d="M 60 34 C 68 34, 74 40, 74 48 L 74 68 C 74 72, 70 76, 66 76" fill="none" stroke="#ffffff" stroke-width="4.5" stroke-linecap="round"/>
                    <rect x="62" y="30" width="8" height="12" rx="2" fill="#ef4444"/>
                </g>
            </svg>
        `,

        // 21. SAN ANDREAS GOV (Capitólio com colunas e frontão)
        gov_portal: `
            <svg viewBox="0 0 100 100" class="w-full h-full select-none" xmlns="http://www.w3.org/2000/svg">
                <defs>
                    <linearGradient id="nx-gov-bg" x1="0%" y1="0%" x2="0%" y2="100%">
                        <stop offset="0%" stop-color="#0284c7"/>
                        <stop offset="100%" stop-color="#0f172a"/>
                    </linearGradient>
                </defs>
                <rect x="4" y="4" width="92" height="92" rx="22" fill="url(#nx-gov-bg)"/>
                <rect x="4.5" y="4.5" width="91" height="91" rx="21.5" fill="none" stroke="rgba(255,255,255,0.4)" stroke-width="1.2"/>
                <polygon points="50,22 22,36 78,36" fill="#f8fafc"/>
                <rect x="22" y="38" width="56" height="4" fill="#cbd5e1"/>
                <rect x="26" y="44" width="6" height="24" rx="1" fill="#f8fafc"/>
                <rect x="38" y="44" width="6" height="24" rx="1" fill="#f8fafc"/>
                <rect x="56" y="44" width="6" height="24" rx="1" fill="#f8fafc"/>
                <rect x="68" y="44" width="6" height="24" rx="1" fill="#f8fafc"/>
                <rect x="18" y="70" width="64" height="6" rx="2" fill="#f8fafc"/>
            </svg>
        `,

        // 22. SECUROSERV COMMAND (Escudo tático azul escuro com estrela de segurança)
        securoserv_command: `
            <svg viewBox="0 0 100 100" class="w-full h-full select-none" xmlns="http://www.w3.org/2000/svg">
                <defs>
                    <linearGradient id="nx-securo-bg" x1="0%" y1="0%" x2="0%" y2="100%">
                        <stop offset="0%" stop-color="#312e81"/>
                        <stop offset="100%" stop-color="#09090b"/>
                    </linearGradient>
                </defs>
                <rect x="4" y="4" width="92" height="92" rx="22" fill="url(#nx-securo-bg)"/>
                <rect x="4.5" y="4.5" width="91" height="91" rx="21.5" fill="none" stroke="rgba(99,102,241,0.5)" stroke-width="1.2"/>
                <path d="M 50 20 L 76 30 C 76 56, 50 78, 50 78 C 50 78, 24 56, 24 30 Z" fill="#1e1b4b" stroke="#6366f1" stroke-width="3"/>
                <polygon points="50,34 54,44 65,44 56,51 60,61 50,55 40,61 44,51 35,44 46,44" fill="#818cf8"/>
            </svg>
        `,

        // 23. DYNASTY 8 REAL ESTATE (Mansão luxuosa com telhado angular rosa/cobre)
        dynasty8_realestate: `
            <svg viewBox="0 0 100 100" class="w-full h-full select-none" xmlns="http://www.w3.org/2000/svg">
                <defs>
                    <linearGradient id="nx-dyn-bg" x1="0%" y1="0%" x2="0%" y2="100%">
                        <stop offset="0%" stop-color="#f43f5e"/>
                        <stop offset="100%" stop-color="#881337"/>
                    </linearGradient>
                </defs>
                <rect x="4" y="4" width="92" height="92" rx="22" fill="url(#nx-dyn-bg)"/>
                <rect x="4.5" y="4.5" width="91" height="91" rx="21.5" fill="none" stroke="rgba(255,255,255,0.4)" stroke-width="1.2"/>
                <polygon points="50,24 20,48 26,48 26,76 74,76 74,48 80,48" fill="#ffffff"/>
                <rect x="42" y="54" width="16" height="22" rx="2" fill="#be123c"/>
                <rect x="30" y="48" width="10" height="10" rx="2" fill="#fda4af"/>
                <rect x="60" y="48" width="10" height="10" rx="2" fill="#fda4af"/>
            </svg>
        `,
        // 24. CYBERDECK EXPLOIT KIT (Matriz hacker neon verde com caveira digital e trilhas)
        cyberdeck: `
            <svg viewBox="0 0 100 100" class="w-full h-full select-none" xmlns="http://www.w3.org/2000/svg">
                <defs>
                    <linearGradient id="nx-cyber-bg" x1="0%" y1="0%" x2="100%" y2="100%">
                        <stop offset="0%" stop-color="#0a1912"/>
                        <stop offset="100%" stop-color="#003822"/>
                    </linearGradient>
                    <linearGradient id="nx-cyber-neon" x1="0%" y1="0%" x2="100%" y2="100%">
                        <stop offset="0%" stop-color="#00ff88"/>
                        <stop offset="100%" stop-color="#00b4d8"/>
                    </linearGradient>
                    <filter id="nx-cyber-glow">
                        <feDropShadow dx="0" dy="0" stdDeviation="2.5" flood-color="#00ff88" flood-opacity="0.8"/>
                    </filter>
                </defs>
                <rect x="4" y="4" width="92" height="92" rx="22" fill="url(#nx-cyber-bg)"/>
                <rect x="4.5" y="4.5" width="91" height="91" rx="21.5" fill="none" stroke="rgba(0,255,136,0.3)" stroke-width="1.2"/>
                <!-- Matrix Circuit Grid Lines -->
                <path d="M 15 25 L 35 25 L 45 35 L 75 35" fill="none" stroke="rgba(0,255,136,0.25)" stroke-width="1.5"/>
                <path d="M 85 75 L 65 75 L 55 65 L 25 65" fill="none" stroke="rgba(0,255,136,0.25)" stroke-width="1.5"/>
                <circle cx="75" cy="35" r="2.5" fill="#00ff88"/>
                <circle cx="25" cy="65" r="2.5" fill="#00ff88"/>
                <!-- Cyber Skull Glyphs -->
                <g filter="url(#nx-cyber-glow)">
                    <path d="M 32 36 C 32 26, 68 26, 68 36 C 68 46, 64 52, 60 56 L 60 66 L 40 66 L 40 56 C 36 52, 32 46, 32 36 Z" fill="url(#nx-cyber-neon)"/>
                    <circle cx="43" cy="42" r="4" fill="#0a1912"/>
                    <circle cx="57" cy="42" r="4" fill="#0a1912"/>
                    <polygon points="50,47 47,53 53,53" fill="#0a1912"/>
                    <!-- Teeth Grid -->
                    <rect x="44" y="60" width="2.5" height="5" fill="#0a1912"/>
                    <rect x="48.5" y="60" width="3" height="5" fill="#0a1912"/>
                    <rect x="53.5" y="60" width="2.5" height="5" fill="#0a1912"/>
                </g>
                <!-- Terminal Prompt prompt icon -->
                <text x="18" y="82" fill="#00ff88" font-family="monospace" font-size="11" font-weight="bold">>_EXEC</text>
            </svg>
        `,

        // 25. USB REMOVABLE EXPLORER (Drive USB metálico prateado/violeta com pinos dourados)
        usb_explorer: `
            <svg viewBox="0 0 100 100" class="w-full h-full select-none" xmlns="http://www.w3.org/2000/svg">
                <defs>
                    <linearGradient id="nx-usb-bg" x1="0%" y1="0%" x2="100%" y2="100%">
                        <stop offset="0%" stop-color="#4c1d95"/>
                        <stop offset="100%" stop-color="#1e1b4b"/>
                    </linearGradient>
                    <linearGradient id="nx-usb-metal" x1="0%" y1="0%" x2="100%" y2="0%">
                        <stop offset="0%" stop-color="#e2e8f0"/>
                        <stop offset="50%" stop-color="#f8fafc"/>
                        <stop offset="100%" stop-color="#94a3b8"/>
                    </linearGradient>
                    <linearGradient id="nx-usb-body" x1="0%" y1="0%" x2="0%" y2="100%">
                        <stop offset="0%" stop-color="#6366f1"/>
                        <stop offset="100%" stop-color="#312e81"/>
                    </linearGradient>
                </defs>
                <rect x="4" y="4" width="92" height="92" rx="22" fill="url(#nx-usb-bg)"/>
                <rect x="4.5" y="4.5" width="91" height="91" rx="21.5" fill="none" stroke="rgba(255,255,255,0.3)" stroke-width="1.2"/>

                <!-- USB Metal Connector Top -->
                <rect x="36" y="18" width="28" height="24" rx="2" fill="url(#nx-usb-metal)"/>
                <!-- Holes in Connector -->
                <rect x="41" y="24" width="6" height="7" rx="1" fill="#1e293b"/>
                <rect x="53" y="24" width="6" height="7" rx="1" fill="#1e293b"/>
                <!-- Gold Pins -->
                <rect x="43" y="27" width="2" height="4" fill="#fbbf24"/>
                <rect x="55" y="27" width="2" height="4" fill="#fbbf24"/>

                <!-- USB Body Drive -->
                <rect x="30" y="38" width="40" height="46" rx="8" fill="url(#nx-usb-body)"/>
                <!-- LED Activity Light -->
                <circle cx="50" cy="46" r="2.5" fill="#38bdf8"/>
                <!-- Grip Lines -->
                <rect x="35" y="56" width="30" height="2" rx="1" fill="rgba(255,255,255,0.2)"/>
                <rect x="35" y="62" width="30" height="2" rx="1" fill="rgba(255,255,255,0.2)"/>
                <rect x="35" y="68" width="30" height="2" rx="1" fill="rgba(255,255,255,0.2)"/>
                <!-- Lanyard Loop -->
                <circle cx="50" cy="78" r="3" fill="#1e1b4b"/>
            </svg>
        `,

        // 26. BUSINESS HUB / ENTERPRISE ERP (Skyscraper corporativo moderno com reflexos e brasão de ouro)
        business_hub: `
            <svg viewBox="0 0 100 100" class="w-full h-full select-none" xmlns="http://www.w3.org/2000/svg">
                <defs>
                    <linearGradient id="nx-biz-bg" x1="0%" y1="0%" x2="100%" y2="100%">
                        <stop offset="0%" stop-color="#1e293b"/>
                        <stop offset="50%" stop-color="#0f172a"/>
                        <stop offset="100%" stop-color="#020617"/>
                    </linearGradient>
                    <linearGradient id="nx-biz-gold" x1="0%" y1="0%" x2="100%" y2="100%">
                        <stop offset="0%" stop-color="#fde047"/>
                        <stop offset="50%" stop-color="#eab308"/>
                        <stop offset="100%" stop-color="#a16207"/>
                    </linearGradient>
                    <linearGradient id="nx-biz-glass" x1="0%" y1="0%" x2="0%" y2="100%">
                        <stop offset="0%" stop-color="#38bdf8" stop-opacity="0.9"/>
                        <stop offset="100%" stop-color="#0284c7" stop-opacity="0.7"/>
                    </linearGradient>
                </defs>
                <rect x="4" y="4" width="92" height="92" rx="22" fill="url(#nx-biz-bg)"/>
                <rect x="4.5" y="4.5" width="91" height="91" rx="21.5" fill="none" stroke="rgba(255,255,255,0.3)" stroke-width="1.2"/>

                <!-- Main Skyscraper Center -->
                <rect x="36" y="22" width="28" height="58" rx="2" fill="url(#nx-biz-glass)"/>
                <!-- Left Tower -->
                <rect x="20" y="38" width="16" height="42" rx="2" fill="#0369a1"/>
                <!-- Right Tower -->
                <rect x="64" y="32" width="16" height="48" rx="2" fill="#0284c7"/>

                <!-- Window Grid Center -->
                <rect x="40" y="28" width="5" height="4" fill="#ffffff" opacity="0.8"/>
                <rect x="48" y="28" width="5" height="4" fill="#ffffff" opacity="0.8"/>
                <rect x="55" y="28" width="5" height="4" fill="#ffffff" opacity="0.8"/>

                <rect x="40" y="38" width="5" height="4" fill="#ffffff" opacity="0.8"/>
                <rect x="48" y="38" width="5" height="4" fill="#ffffff" opacity="0.8"/>
                <rect x="55" y="38" width="5" height="4" fill="#ffffff" opacity="0.8"/>

                <rect x="40" y="48" width="5" height="4" fill="#ffffff" opacity="0.8"/>
                <rect x="48" y="48" width="5" height="4" fill="#ffffff" opacity="0.8"/>
                <rect x="55" y="48" width="5" height="4" fill="#ffffff" opacity="0.8"/>

                <!-- Gold Growth Arrow -->
                <path d="M 22 72 L 44 52 L 58 62 L 78 40" fill="none" stroke="url(#nx-biz-gold)" stroke-width="4.5" stroke-linecap="round" stroke-linejoin="round"/>
                <polygon points="78,34 86,40 76,46" fill="#fde047"/>

                <!-- Briefcase / Deal Badge -->
                <circle cx="50" cy="72" r="11" fill="#0f172a" stroke="url(#nx-biz-gold)" stroke-width="2"/>
                <rect x="44" y="68" width="12" height="8" rx="1.5" fill="url(#nx-biz-gold)"/>
                <path d="M 47 68 L 47 66 C 47 64.5, 53 64.5, 53 66 L 53 68" fill="none" stroke="url(#nx-biz-gold)" stroke-width="1.5"/>
            </svg>
        `
    };

    /**
     * Retorna o SVG de alta definição para um aplicativo ou recurso do sistema.
     * @param {string} appId
     * @returns {string} Código SVG renderizado
     */
    function getIcon(appId) {
        if (!appId) return ICONS.finder;
        const normalized = appId.toLowerCase().trim();
        if (ICONS[normalized]) {
            return ICONS[normalized];
        }
        // Mapeamentos de aliases
        if (normalized.includes('business') || normalized.includes('empresa') || normalized.includes('erp') || normalized.includes('corp')) return ICONS.business_hub;
        if (normalized.includes('cyber') || normalized.includes('deck') || normalized.includes('exploit')) return ICONS.cyberdeck;
        if (normalized.includes('usb') || normalized.includes('pendrive') || normalized.includes('remov')) return ICONS.usb_explorer;
        if (normalized.includes('gas') || normalized.includes('posto') || normalized.includes('fuel')) return ICONS.gas_manager;
        if (normalized.includes('gov') || normalized.includes('prefeit') || normalized.includes('lei')) return ICONS.gov_portal;
        if (normalized.includes('securo') || normalized.includes('gruppe') || normalized.includes('tatico') || normalized.includes('guard')) return ICONS.securoserv_command;
        if (normalized.includes('dynasty') || normalized.includes('imovel') || normalized.includes('house') || normalized.includes('realestate')) return ICONS.dynasty8_realestate;
        if (normalized.includes('safari') || normalized.includes('web')) return ICONS.browser;
        if (normalized.includes('store') || normalized.includes('market')) return ICONS.app_store;
        if (normalized.includes('config') || normalized.includes('ajuste') || normalized.includes('preferenc')) return ICONS.settings;
        if (normalized.includes('bloco') || normalized.includes('txt')) return ICONS.notes;
        if (normalized.includes('page') || normalized.includes('word') || normalized.includes('contrat')) return ICONS.docs;
        if (normalized.includes('calc')) return ICONS.calculator;
        if (normalized.includes('stock') || normalized.includes('acao') || normalized.includes('invest')) return ICONS.stocks;
        if (normalized.includes('job') || normalized.includes('rh') || normalized.includes('carreira')) return ICONS.jobs_hub;
        if (normalized.includes('bash') || normalized.includes('hack') || normalized.includes('cmd')) return ICONS.terminal;
        if (normalized.includes('bank') || normalized.includes('fleeca') || normalized.includes('maze') || normalized.includes('banco')) return ICONS.online_banking;
        if (normalized.includes('coin') || normalized.includes('qbit') || normalized.includes('carteira')) return ICONS.crypto;
        if (normalized.includes('silk') || normalized.includes('dark') || normalized.includes('deep')) return ICONS.darkweb;
        if (normalized.includes('car') || normalized.includes('boost') || normalized.includes('vin')) return ICONS.boosting;
        if (normalized.includes('print') || normalized.includes('3d') || normalized.includes('craft')) return ICONS.ifruit_workshop;
        if (normalized.includes('ghost') || normalized.includes('fraud') || normalized.includes('card') || normalized.includes('msr')) return ICONS.card_forge;
        if (normalized.includes('crime') || normalized.includes('csi') || normalized.includes('peric') || normalized.includes('forens') || normalized.includes('dna')) return ICONS.crimescene;
        if (normalized.includes('cop') || normalized.includes('polic') || normalized.includes('mdt')) return ICONS.police_mdt;
        if (normalized.includes('camera') || normalized.includes('cam') || normalized.includes('cctv')) return ICONS.cctv_viewer;
        if (normalized.includes('lixeira') || normalized.includes('trash')) return ICONS.trash;
        if (normalized.includes('power') || normalized.includes('desligar') || normalized.includes('shut')) return ICONS.power;

        return ICONS.finder;
    }

    return {
        getIcon: getIcon,
        icons: ICONS
    };
})();
