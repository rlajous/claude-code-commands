import { defineCollection } from 'astro:content';
import { docsLoader } from '@astrojs/starlight/loaders';
import { docsSchema } from '@astrojs/starlight/schema';

const generatedPrefix = /^generated\//;
const markdownExtension = /\.(?:md|mdx)$/;

export const collections = {
  docs: defineCollection({
    loader: docsLoader({
      generateId: ({ entry }) => entry.replace(generatedPrefix, '').replace(markdownExtension, ''),
    }),
    schema: docsSchema(),
  }),
};
