// FAQ copy for /how-it-works/ and /support/. Plain text answers; every answer must match
// docs/03-feature-spec.md. In-app labels follow the Settings list in spec §13.
import type { FaqItem } from '../lib/schema';

export const howFaq: FaqItem[] = [
  {
    question: 'What if my partner does not answer my request?',
    answer:
      'A request stays open for 5 minutes. If your partner has notifications off or has not answered after 2 minutes, they also get an email with a link and a 6-digit code they can share with you. If nobody answers, nothing is lost: you can try again, or use your minutes.',
  },
  {
    question: 'Does it work without an internet connection?',
    answer:
      'Protected time and unlock windows run on your phone, so they keep working offline. Scanning your partner’s code in person also works fully offline. Asking your partner and spending minutes need a connection.',
  },
  {
    question: 'How long can an unlock be?',
    answer:
      'You choose 15, 30 or 60 minutes each time, and 30 is the default. With premium you can pick any length in 15-minute steps. When the time is up, protected time simply resumes.',
  },
  {
    question: 'Why do minutes expire?',
    answer:
      'Each minute lasts 7 days from when you earn it, and the app shows you what expires when. Minutes are meant to be earned and enjoyed in the same week, not saved up to get around protected time.',
  },
  {
    question: 'What happens after an emergency unlock?',
    answer:
      'You get 15 minutes right away, no questions asked. It borrows 15 minutes, which your next earned minutes pay back, and a new streak starts that day. Your partner sees a simple, neutral note that you used it. You can use it once every 7 days.',
  },
  {
    question: 'Can one of us change the schedule alone?',
    answer:
      'Making protected time stricter, such as adding hours or apps, applies right away. Loosening it is something you agree on together: your partner gets a request and can approve it or suggest talking it over. Either of you can also unpair at any time, and then your schedule is entirely your own.',
  },
];

export const supportFaq: FaqItem[] = [
  {
    question: 'How do I pair with my partner?',
    answer:
      'In the app, tap Invite partner. You can share a link, read out a 6-character code, or show a QR code in person. Invites last 72 hours. Your partner accepts, you both confirm, and you are paired.',
  },
  {
    question: 'How do I unpair?',
    answer:
      'Open Settings in the app, go to your partner, choose Unpair and confirm once. It takes effect immediately and does not need your partner’s approval. Your partner gets a short, neutral notification. Protected time stays on your phone with its current schedule, and from then on you can change it freely.',
  },
  {
    question: 'How do I change which apps are paused?',
    answer:
      'Open Settings in the app and go to Paused apps. You choose apps in Apple’s own picker. Adding apps applies right away. Removing apps loosens protected time, so your partner is asked to agree. Your list stays on your phone and is never shared.',
  },
  {
    question: 'I need an app right now. What can I do?',
    answer:
      'Open the app and choose a way to unlock: scan your partner’s code if you are together, ask your partner, or spend your minutes. If none of those fits, use the emergency unlock for 15 minutes. It is always available, once every 7 days.',
  },
  {
    question: 'How do I cancel my subscription?',
    answer:
      'Subscriptions are managed by Apple. On your iPhone open Settings, tap your name, then Subscriptions, choose the app and tap Cancel Subscription. Premium stays active until the end of the period you paid for. Deleting the app or your account does not cancel a subscription.',
  },
  {
    question: 'How do I get a refund?',
    answer:
      'Refunds for App Store purchases are handled by Apple. Go to reportaproblem.apple.com, sign in, and choose the purchase.',
  },
  {
    question: 'How do I get a copy of my data?',
    answer:
      'Open Settings in the app and choose Export my data. You receive a file with the information the app holds about you.',
  },
  {
    question: 'Protected time is not pausing my apps. What should I check?',
    answer:
      'Check that Screen Time access is still allowed for the app in your iPhone settings, that you have chosen at least one app to pause, and that the current time is inside your schedule. If it still does not work, write to us and we will help.',
  },
];
