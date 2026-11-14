// FAQ copy. Answers are plain text so the same text feeds the page and the FAQPage markup.
// Every answer must match docs/03-feature-spec.md.
import { site, price } from '../config/site';
import type { FaqItem } from '../lib/schema';

export const homeFaq: FaqItem[] = [
  {
    question: 'Is this a way for my partner to control me?',
    answer:
      'No, and the app is built so it cannot be. You both have exactly the same powers and there is no admin. Either of you can unpair at any time, instantly, without the other agreeing. Your partner never sees which apps you paused, what you do in them, or where you are. And an emergency unlock is always there.',
  },
  {
    question: 'What can my partner see?',
    answer:
      'Only what the app itself creates: your minutes, the requests you send each other, challenges, kudos and your shared streak. Never your apps, your messages, your location or your screen time.',
  },
  {
    question: 'What is protected time?',
    answer:
      'A schedule you agree on, when the apps you each chose are paused. It starts at 6 PM to 9 AM every day, so evenings and mornings are yours again, and you can change it. Making it stricter applies right away. Loosening it is something you agree on together.',
  },
  {
    question: 'What if I really need an app during protected time?',
    answer:
      'You have three warm ways to unlock: scan the code on your partner’s phone when you are together, ask your partner and they tap "Go for it", or spend minutes you earned. If none of that fits, an emergency unlock gives you 15 minutes, once every 7 days, with no approval needed.',
  },
  {
    question: 'Which apps get paused?',
    answer:
      'You choose, on your own phone, using Apple’s Screen Time picker. We suggest social media. Phone, Messages, Maps and your bank are best left out. Your choices stay on your phone and are never shared.',
  },
  {
    question: 'How do we earn minutes?',
    answer:
      'By doing things together and for each other: a phone-free dinner, a walk, a note. Your partner confirms with one tap and the minutes arrive. With premium your partner can also send kudos, minutes given just because they noticed you. Minutes last 7 days, so they are for using, not saving up.',
  },
  {
    question: 'How much does it cost?',
    answer: `The free version has pairing, protected time, every way to unlock and 5 challenges. Premium is ${price.yearlyForBoth}, or ${price.lifetimeForBoth}. One of you pays and both of you get premium. There is a ${site.pricing.trialDays}-day free trial.`,
  },
  {
    question: 'Does it work on Android?',
    answer:
      'The iPhone app comes first and the Android app follows. Until then, the plan is for a partner on Android to answer requests by email and join in with challenges and kudos on the web. Protected time will not run on their own phone until the Android app arrives.',
  },
  {
    question: 'When can we get it?',
    answer:
      'We are building it now. Join the waitlist and we will email you when it is ready.',
  },
];

export const pricingFaq: FaqItem[] = [
  {
    question: 'Do we both have to pay?',
    answer: `No. Every price is one price for the couple. One of you pays ${price.yearly} a year or ${price.lifetime} once, and both of you get premium.`,
  },
  {
    question: 'What is in the free version?',
    answer:
      'Pairing, protected time with one schedule, all three ways to unlock plus the emergency unlock, earned minutes, 5 preset challenges, this week’s summary report, and widgets. Free stays free.',
  },
  {
    question: 'How does the free trial work?',
    answer: `Premium yearly starts with a ${site.pricing.trialDays}-day free trial. The trial begins when the first of you opts in, and it covers both of you. If you do not continue, you keep the free version and the minutes you earned.`,
  },
  {
    question: 'What happens if we stop premium?',
    answer:
      'You keep your earned minutes. Custom challenges and extra schedules are hidden, not deleted, and they come back if you subscribe again.',
  },
  {
    question: 'What happens to premium if we unpair?',
    answer:
      'Premium stays with the person who paid. The other person moves to the free version.',
  },
  {
    question: 'How do refunds and cancelling work?',
    answer:
      'Purchases are made through the App Store, so you cancel in your Apple subscription settings and refunds are handled by Apple.',
  },
  {
    question: 'Is there a monthly plan?',
    answer: 'Not at launch. There is a yearly plan and a one-time lifetime purchase, each covering both of you.',
  },
];
