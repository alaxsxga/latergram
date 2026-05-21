import Foundation
import Supabase

let supabase = SupabaseClient(
    supabaseURL: URL(string: Secrets.supabaseURL)!,
    supabaseKey: Secrets.supabaseAnonKey,
    options: SupabaseClientOptions(
        auth: SupabaseClientOptions.AuthOptions(
            emitLocalSessionAsInitialSession: true
        )
    )
)
