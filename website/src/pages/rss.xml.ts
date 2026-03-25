import rss from '@astrojs/rss';
import type { APIContext } from 'astro';
import { getCollection } from 'astro:content';

export async function GET(context: APIContext) {
  const docs = await getCollection('docs');
  const blogPosts = docs
    .filter((entry) => entry.id.startsWith('blog/') && !entry.id.endsWith('blog/'))
    .sort((a, b) => {
      const dateA = a.data.date ? new Date(a.data.date).getTime() : 0;
      const dateB = b.data.date ? new Date(b.data.date).getTime() : 0;
      return dateB - dateA;
    });

  return rss({
    title: 'Coding Standards Blog',
    description: 'Updates on unified coding standards for every AI coding assistant.',
    site: context.site!.toString(),
    items: blogPosts.map((post) => ({
      title: post.data.title,
      pubDate: post.data.date ? new Date(post.data.date) : new Date(),
      link: `/blog/${post.id.replace('blog/', '')}/`,
    })),
    customData: '<language>en</language>',
  });
}
