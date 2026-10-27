-- 0074 - Los usuarios de locales y riders pasan a @modoya.app
--
-- `admin-crear-usuario` los generaba como `nombre@modoya.com`, con el comentario
-- "solo es un identificador: no se le manda correo". Era cierto mientras
-- Supabase no mandaba mails. Desde que manda (Resend, 26/10/2026) dejó de
-- serlo: cualquiera puede pedir "recuperar contraseña" para un usuario, y
-- `modoya.com` **no es nuestro**: tiene correo real de otra empresa (Outlook).
-- El link para elegir una contraseña nueva le habría llegado a ella.
--
-- `modoya.app` sí es nuestro. Hoy su correo entrante es el reenvío de
-- Namecheap sin ninguna casilla, así que un mail a esos usuarios no le llega a
-- nadie; y si algún día se arma un reenvío para un local, le llega a quien
-- decida MODO YA.
--
-- Al 26/10/2026 había tres usuarios así, los tres de prueba y sin ningún
-- ingreso. La app sigue aceptando el usuario viejo (`@modoya.com`) al entrar.

update auth.users
   set email = replace(email, '@modoya.com', '@modoya.app')
 where email like '%@modoya.com';

-- La identidad del proveedor email guarda su propia copia del email.
update auth.identities
   set identity_data = jsonb_set(identity_data, '{email}',
                                 to_jsonb(replace(identity_data->>'email', '@modoya.com', '@modoya.app')))
 where provider = 'email'
   and identity_data->>'email' like '%@modoya.com';
