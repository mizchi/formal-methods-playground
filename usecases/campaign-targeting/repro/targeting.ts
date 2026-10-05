// A minimal targeting evaluator, shaped like the ones that read campaign JSON.
// A rule matches when include holds, exclude does not, the user is not
// denylisted, and the allowlist admits the user.

export type User = { id: string; country?: string; age: number };
export type Config = {
  campaign: string;
  include?: { country?: string[]; age?: { gte?: number; lt?: number } };
  exclude?: { country?: string[] };
  allowlist?: string[];
};

function inRange(age: number, range?: { gte?: number; lt?: number }): boolean {
  if (!range) return true;
  if (range.gte !== undefined && !(age >= range.gte)) return false;
  if (range.lt !== undefined && !(age < range.lt)) return false;
  return true;
}

function countryIn(country: string | undefined, list: string[]): boolean {
  // A missing or malformed country is in no list. That fails closed for
  // include, and fails open for exclude.
  return country !== undefined && list.includes(country);
}

export function matches(user: User, config: Config, denylist: Set<string> = new Set()): boolean {
  const inc = config.include ?? {};
  const exc = config.exclude ?? {};
  if (inc.country && !countryIn(user.country, inc.country)) return false;
  if (!inRange(user.age, inc.age)) return false;
  if (exc.country && countryIn(user.country, exc.country)) return false;
  if (denylist.has(user.id)) return false;
  const allow = config.allowlist ?? [];
  // Empty allowlist is read as "no restriction". The docs do not say this.
  if (allow.length > 0 && !allow.includes(user.id)) return false;
  return true;
}
