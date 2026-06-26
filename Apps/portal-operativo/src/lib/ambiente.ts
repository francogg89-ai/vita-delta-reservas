// Discriminador de ambiente del frontend (sub-slice 3).
//
// Fuente de verdad UNICA: la URL de Supabase (VITE_SUPABASE_URL). NO existe
// VITE_AMBIENTE: no se duplica la fuente de verdad. El ambiente se deriva del
// proyecto al que apunta el build, igual que el resto del proyecto discrimina
// ambiente por URL/identidad y nunca por payload.
//
//  - URL contiene el ref del proyecto TEST  -> 'test'        (banner de prueba).
//  - cualquier otra cosa (URL ausente, ref  -> 'desconocido' (estado DEFENSIVO:
//    distinto, typo, build mal configurado)    banner de advertencia; nunca se
//                                               asume produccion segura).
//
// El reconocimiento de OPS (otro ref -> sin banner) se agrega en la promocion a
// OPS, que es otra etapa. Hasta entonces, todo lo no-TEST cae en 'desconocido'
// a proposito: un build sin configurar grita en vez de parecer produccion.

const REF_TEST = 'bdskhhbmcksskkzqkcdp';

export type Ambiente = 'test' | 'desconocido';

const urlSupabase: string = import.meta.env.VITE_SUPABASE_URL ?? '';

export const AMBIENTE: Ambiente = urlSupabase.includes(REF_TEST) ? 'test' : 'desconocido';

// En ambos estados actuales (test y defensivo) se muestra banner. Solo un futuro
// 'ops' reconocido no lo mostraria (rama a agregar en la etapa OPS).
export const MOSTRAR_BANNER: boolean = AMBIENTE === 'test' || AMBIENTE === 'desconocido';
