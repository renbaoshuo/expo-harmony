import js from '@eslint/js';
import tseslint from 'typescript-eslint';
import react from 'eslint-plugin-react';
import stylistic from '@stylistic/eslint-plugin';
import globals from 'globals';

export default tseslint.config(
  {
    ignores: [
      '**/dist/**',
      '**/build/**',
      '**/.cxx/**',
      '**/generated/**',
      '**/harmony/**',
      '**/oh_modules/**',
      '**/.expo/**',
      '**/.hvigor/**',
    ],
  },
  js.configs.recommended,
  ...tseslint.configs.recommended,
  react.configs.flat.recommended,
  react.configs.flat['jsx-runtime'],
  {
    files: ['**/*.{ts,tsx,js,jsx}'],
    languageOptions: {
      ecmaVersion: 'latest',
      sourceType: 'module',
      globals: {
        ...globals.node,
      },
    },
    settings: {
      react: {
        version: 'detect',
      },
    },
  },
  stylistic.configs.customize({
    indent: 2,
    quotes: 'single',
    semi: true,
    jsx: true,
  }),
  {
    files: ['**/*.js'],
    languageOptions: {
      sourceType: 'commonjs',
    },
    rules: {
      '@typescript-eslint/no-require-imports': 'off',
    },
  },
  {
    rules: {
      'no-constant-binary-expression': 'warn',
      '@stylistic/brace-style': ['error', '1tbs'],
      '@stylistic/jsx-wrap-multilines': 'off',
      '@stylistic/jsx-one-expression-per-line': 'off',
      '@stylistic/jsx-closing-tag-location': ['error', 'line-aligned'],
      '@stylistic/comma-dangle': [
        'error',
        {
          arrays: 'always-multiline',
          objects: 'always-multiline',
          imports: 'always-multiline',
          exports: 'always-multiline',
          functions: 'never',
          enums: 'always-multiline',
          generics: 'always-multiline',
          tuples: 'always-multiline',
        },
      ],
      '@stylistic/max-len': [
        'warn',
        {
          code: 120,
          ignoreStrings: true,
          ignoreTemplateLiterals: true,
          ignoreComments: true,
          ignoreUrls: true,
          ignoreRegExpLiterals: true,
        },
      ],
      '@typescript-eslint/no-unused-vars': [
        'error',
        {
          args: 'all',
          argsIgnorePattern: '^_',
          caughtErrors: 'all',
          caughtErrorsIgnorePattern: '^_',
          destructuredArrayIgnorePattern: '^_',
          varsIgnorePattern: '^_',
          ignoreRestSiblings: true,
        },
      ],
    },
  }
);
