-- 0026 - Pago con tarjeta
--
-- El cliente elige como paga al hacer el pedido: efectivo, tarjeta (debito o
-- credito, con posnet al recibir) o transferencia. Va en su propio archivo
-- porque Postgres no deja usar un valor nuevo de un enum en la misma
-- transaccion que lo agrega (lo usa 0027).

alter type public.metodo_pago add value if not exists 'tarjeta' after 'efectivo';
