import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';
import starlightBlog from 'starlight-blog';

export default defineConfig({
  site: 'https://coding-standards.c65llc.com',
  integrations: [
    starlight({
      plugins: [starlightBlog()],
      title: 'Coding Standards',
      description: 'Unified coding standards for every AI coding assistant.',
      social: [
        { icon: 'github', label: 'GitHub', href: 'https://github.com/c65llc/coding-standards' },
        { icon: 'rss', label: 'RSS Feed', href: 'https://coding-standards.c65llc.com/rss.xml' },
      ],
      defaultLocale: 'root',
      locales: {
        root: { label: 'English', lang: 'en' },
      },
      sidebar: [
        {
          label: 'Getting Started',
          items: [{ autogenerate: { directory: 'getting-started' } }],
        },
        {
          label: 'Standards',
          collapsed: true,
          items: [
            {
              label: 'Architecture',
              items: [{ autogenerate: { directory: 'standards/architecture' } }],
            },
            {
              label: 'Languages',
              items: [{ autogenerate: { directory: 'standards/languages' } }],
            },
            {
              label: 'Process',
              items: [{ autogenerate: { directory: 'standards/process' } }],
            },
            {
              label: 'Security',
              items: [{ autogenerate: { directory: 'standards/security' } }],
            },
          ],
        },
        {
          label: 'Guides',
          items: [{ autogenerate: { directory: 'guides' } }],
        },
        {
          label: 'Reference',
          items: [{ autogenerate: { directory: 'reference' } }],
        },
      ],
      customCss: [],
      head: [
        {
          tag: 'meta',
          attrs: {
            property: 'og:image',
            content: 'https://coding-standards.c65llc.com/og-image.png',
          },
        },
        {
          tag: 'link',
          attrs: {
            rel: 'alternate',
            type: 'application/rss+xml',
            title: 'Coding Standards Blog',
            href: 'https://coding-standards.c65llc.com/rss.xml',
          },
        },
      ],
    }),
  ],
});
