/// The vendor's hosted service (Supabase): accounts, orgs, and subscribed
/// orgs' data.
///
/// The publishable key is meant to ship in the app: on its own it reaches
/// nothing (the database's rules give signed-out visitors no access);
/// what a signed-in person can reach is decided by the rules
/// (`supabase/migrations/*_orgs.sql`). Never put a secret key here.
abstract final class HostedService {
  static const url = 'https://rrnwyyuuekfrqxdieulf.supabase.co';
  static const publishableKey =
      'sb_publishable_zyj5xj3YnOianV66nrq5IA_5-sYDOVv';

  /// The bucket files are kept in, under `<orgId>/`.
  static const bucket = 'codename';

  /// Digits in the sign-in code (the project's email OTP length).
  static const codeLength = 6;
}
