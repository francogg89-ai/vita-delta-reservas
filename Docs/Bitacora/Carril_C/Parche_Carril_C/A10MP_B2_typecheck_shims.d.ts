// Ambient shims SOLO para typecheck local del Edge Function Deno (no se despliega esto).
declare const Deno: {
  env: { get(key: string): string | undefined };
  serve(handler: (req: Request) => Response | Promise<Response>): unknown;
};
declare module 'jsr:@supabase/supabase-js@2' {
  export function createClient(url: string, key: string, options?: unknown): {
    auth: { getUser(jwt?: string): Promise<{ data: { user: { id?: string } | null }; error: unknown }> };
    from(table: string): {
      select(cols?: string): any;
      [k: string]: any;
    };
    [k: string]: any;
  };
}
