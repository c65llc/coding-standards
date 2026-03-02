import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';

export default defineConfig({
  site: 'https://coding_standards.c65llc.com',
  legacy: {
    collections: true,
  },
  integrations: [
    starlight({
      title: 'Coding Standards',
      description: 'Unified coding standards for every AI coding assistant.',
      social: {
        github: 'https://github.com/c65llc/coding_standards',
      },
      defaultLocale: 'root',
      locales: {
        root: { label: 'English', lang: 'en' },
      },
      sidebar: [
        {
          label: 'Getting Started',
          autogenerate: { directory: 'getting-started' },
        },
        {
          label: 'Standards',
          collapsed: true,
          items: [
            {
              label: 'Architecture',
              autogenerate: { directory: 'standards/architecture' },
            },
            {
              label: 'Languages',
              autogenerate: { directory: 'standards/languages' },
            },
            {
              label: 'Process',
              autogenerate: { directory: 'standards/process' },
            },
          ],
        },
        {
          label: 'Guides',
          autogenerate: { directory: 'guides' },
        },
        {
          label: 'Reference',
          autogenerate: { directory: 'reference' },
        },
      ],
      customCss: [],
      head: [
        {
          tag: 'meta',
          attrs: {
            property: 'og:image',
            content: 'https://coding_standards.c65llc.com/og-image.png',
          },
        },
      ],
    }),
  ],
});
