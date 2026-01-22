# CLAUDE.md

This file provides guidance to Claude Code when working with this React Native project.

## Project Overview

A React Native mobile app built with Expo, featuring TypeScript, React Navigation, and native module integration.

**Tech Stack:**

- Framework: React Native with Expo SDK 50
- Language: TypeScript
- Navigation: React Navigation 6
- State: Zustand / TanStack Query
- Styling: NativeWind (Tailwind for RN)
- Package Manager: Yarn

## Development Commands

```bash
# Install dependencies
yarn install

# Start development
yarn start                     # Start Expo dev server
yarn ios                       # Run on iOS simulator
yarn android                   # Run on Android emulator

# Testing
yarn test                      # Jest tests
yarn test:e2e                  # Detox E2E tests

# Code quality
yarn lint                      # ESLint
yarn typecheck                 # TypeScript check
yarn format                    # Prettier

# Building
eas build --platform ios --profile development
eas build --platform android --profile development
eas build --platform all --profile production

# Submitting
eas submit --platform ios
eas submit --platform android
```

## Project Structure

```
app/
├── (tabs)/                # Tab navigator screens
│   ├── index.tsx          # Home tab
│   ├── profile.tsx        # Profile tab
│   └── _layout.tsx        # Tab layout
├── (auth)/                # Auth flow screens
│   ├── login.tsx
│   └── register.tsx
└── _layout.tsx            # Root layout

components/
├── ui/                    # Reusable UI components
├── forms/                 # Form components
└── layouts/               # Layout components

lib/
├── api/                   # API client
├── hooks/                 # Custom hooks
├── stores/                # Zustand stores
└── utils/                 # Utilities

assets/
├── images/
└── fonts/

constants/
├── Colors.ts
└── Layout.ts
```

## Git Workflow

Uses Claude Code commands with Linear integration:

- `/start` → Create branch from Linear ticket
- `/commit` → Commit with `[Type] Message (TICKET-ID)`
- `/finish` → Create PR to develop
- `/release` → Create release build

## Code Standards

### Component Structure

```tsx
import { View, Text } from 'react-native';

interface ButtonProps {
  title: string;
  onPress: () => void;
  variant?: 'primary' | 'secondary';
}

export function Button({ title, onPress, variant = 'primary' }: ButtonProps) {
  return (
    <Pressable
      onPress={onPress}
      className={variant === 'primary' ? 'bg-blue-500' : 'bg-gray-200'}
    >
      <Text className="text-white font-medium">{title}</Text>
    </Pressable>
  );
}
```

### File Naming

- Components: PascalCase (`UserCard.tsx`)
- Screens: PascalCase (`HomeScreen.tsx`)
- Hooks: camelCase with `use` (`useAuth.ts`)
- Utilities: camelCase (`formatDate.ts`)

### Navigation

Use typed navigation with React Navigation:

```tsx
type RootStackParamList = {
  Home: undefined;
  Profile: { userId: string };
  Settings: undefined;
};
```

## Environment Variables

Using Expo's env system:

```bash
# .env
EXPO_PUBLIC_API_URL=https://api.example.com
EXPO_PUBLIC_APP_ENV=development

# Secrets (not in .env)
EAS_BUILD_API_KEY=xxx
```

## Testing Guidelines

- Unit tests with Jest and React Native Testing Library
- E2E tests with Detox
- Test user flows, not implementation

```tsx
import { render, fireEvent } from '@testing-library/react-native';

test('button calls onPress', () => {
  const onPress = jest.fn();
  const { getByText } = render(<Button title="Click" onPress={onPress} />);
  fireEvent.press(getByText('Click'));
  expect(onPress).toHaveBeenCalled();
});
```

## Build & Deployment

Using EAS Build:

```bash
# Development build
eas build --platform all --profile development

# Preview build (internal testing)
eas build --platform all --profile preview

# Production build
eas build --platform all --profile production
```

## Platform-Specific Code

```tsx
import { Platform } from 'react-native';

const styles = {
  shadow: Platform.select({
    ios: { shadowColor: '#000', shadowOffset: { width: 0, height: 2 } },
    android: { elevation: 4 },
  }),
};
```
