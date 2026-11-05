-- Remove direct RPC execution from trigger-only SECURITY DEFINER functions.
-- Their triggers continue to invoke them; API roles cannot call them directly.
revoke all on function public.handle_new_user() from public, anon, authenticated;
revoke all on function public.musea_limit_creator_portfolio_items() from public, anon, authenticated;
