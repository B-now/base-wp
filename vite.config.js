import { defineConfig } from 'vite'
import laravel from 'laravel-vite-plugin'
import fg from 'fast-glob'
import { wordpressPlugin, wordpressThemeJson } from '@roots/vite-plugin'
import { viteStaticCopy } from 'vite-plugin-static-copy'
import path from 'path'

// 🔍 Scan automatique des fichiers pages
const pagesStylesFiles = fg.sync('resources/css/pages/**/*.scss')
const pagesScriptsFiles = fg.sync('resources/js/pages/**/*.{js,ts}')
const componentsStylesFiles = fg.sync('resources/css/components/**/*.scss')
const componentsScriptsFiles = fg.sync('resources/js/components/**/*.{js,ts}')
console.log('🔍 Styles Pages:', pagesStylesFiles)
console.log('🔍 Scripts Pages:', pagesScriptsFiles)
console.log('🔍 Styles Components:', componentsStylesFiles)
console.log('🔍 Scripts Components:', componentsScriptsFiles)

export default defineConfig({
  server: {
    host: 'localhost',
    port: 3000,
    proxy: {
      '^/(?!app/themes/name/public/build/).*': {
        target: 'http://localhost:8000',
        changeOrigin: true,
        secure: false,
      },
    },
  },

  base: '/app/themes/name/public/build/',

  plugins: [
    laravel({
      input: [
        'resources/css/app.scss',
        'resources/js/app.ts',
        'resources/css/editor.scss',
        'resources/js/editor.ts',
        ...pagesStylesFiles,
        ...pagesScriptsFiles,
        ...componentsStylesFiles,
        ...componentsScriptsFiles,
      ],
      refresh: true,
    }),

    wordpressPlugin(),

    wordpressThemeJson({
      disableTailwindColors: true,
      disableTailwindFonts: true,
      disableTailwindFontSizes: true,
    }),

    viteStaticCopy({
      targets: [
        {
          src: 'resources/images/*',
          dest: 'images/',
        },
      ],
    }),
  ],

  resolve: {
    alias: {
      '@scripts': '/resources/js',
      '@styles': '/resources/css',
      '@fonts': '/resources/fonts',
      '@images': '/resources/images',
    },
  },
})


