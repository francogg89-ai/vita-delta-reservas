/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        // Identidad Vita Delta: río/delta. Base fría (no cream), acento teal de río.
        ink: '#10211f', // slate-verde casi negro: texto y títulos
        river: {
          DEFAULT: '#0f6e7d', // teal de río: acento primario
          dark: '#0a4e58', // hover / texto sobre superficies claras
          light: '#e6f1f2', // superficie teal muy clara: ítem activo / chips
        },
        sand: '#e9e3d6', // arena cálida: bordes y divisores sutiles
        mist: '#f4f6f5', // fondo de página: off-white frío
        reed: '#5d7a6e', // junco apagado: texto secundario
      },
      fontFamily: {
        sans: ['Inter', 'ui-sans-serif', 'system-ui', 'sans-serif'],
      },
    },
  },
  plugins: [],
};
