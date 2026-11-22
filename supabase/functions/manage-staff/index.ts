import { createClient } from "npm:@supabase/supabase-js@2.119.2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const staffRoles = new Set([
  "COCINERO",
  "JEFE_COCINA",
  "MESERO",
  "CAJERO",
]);
const employmentStatuses = new Set([
  "ACTIVO",
  "VACACIONES",
  "LICENCIA",
  "INACTIVO",
]);

type StaffRequest = {
  action: "create" | "update" | "reset_password" | "complete_password_change";
  id?: string;
  name?: string;
  email?: string;
  role?: string;
  password?: string;
  documentId?: string;
  personalEmail?: string;
  phone?: string;
  address?: string;
  department?: string;
  employmentStatus?: string;
};

function response(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function requiredString(value: unknown, label: string, minLength = 1): string {
  if (typeof value !== "string" || value.trim().length < minLength) {
    throw new Error(`${label} no es válido.`);
  }
  return value.trim();
}

function optionalString(
  value: unknown,
  label: string,
  maxLength: number,
): string {
  if (value === undefined) return "";
  if (typeof value !== "string" || value.trim().length > maxLength) {
    throw new Error(`${label} no es válido.`);
  }
  return value.trim();
}

const emailPattern = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;

const requirePasswordChange = true;

function readPassword(value: unknown) {
  if (
    typeof value !== "string" || value.trim().length < 8 ||
    new TextEncoder().encode(value).length > 72
  ) {
    return null;
  }
  return value;
}

function readProfile(input: StaffRequest) {
  const name = requiredString(input.name, "El nombre");
  const email = requiredString(input.email, "El correo").toLowerCase();
  const role = requiredString(input.role, "El rol");
  const status = input.employmentStatus ?? "ACTIVO";
  const personalEmail = optionalString(
    input.personalEmail,
    "El correo personal",
    254,
  );
  if (
    email.length > 254 || !emailPattern.test(email) ||
    !employmentStatuses.has(status) ||
    (personalEmail && !emailPattern.test(personalEmail))
  ) {
    throw new Error("Revisa los correos y el estado laboral.");
  }
  return {
    nombre_completo: name,
    correo: email,
    rol: role,
    activo: status !== "INACTIVO",
    estado_laboral: status,
    documento_identidad: optionalString(input.documentId, "El documento", 32),
    correo_personal: personalEmail,
    telefono: optionalString(input.phone, "El teléfono", 32),
    direccion: optionalString(input.address, "La dirección", 500),
    departamento: optionalString(input.department, "El departamento", 100),
  };
}

export async function handleRequest(request: Request): Promise<Response> {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return response({ error: "Método no permitido." }, 405);
  }

  try {
    const authorization = request.headers.get("Authorization");
    if (!authorization?.startsWith("Bearer ")) {
      return response({ error: "Se requiere una sesión autenticada." }, 401);
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!supabaseUrl || !anonKey || !serviceKey) {
      throw new Error("Falta configurar el entorno de Supabase.");
    }

    const token = authorization.slice("Bearer ".length);
    const authClient = createClient(supabaseUrl, anonKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: authData, error: authError } = await authClient.auth.getUser(
      token,
    );
    if (authError || !authData.user) {
      return response({ error: "La sesión no es válida." }, 401);
    }

    const adminClient = createClient(supabaseUrl, serviceKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    let input: StaffRequest;
    try {
      input = await request.json();
    } catch {
      return response(
        { error: "La solicitud no tiene un formato válido." },
        400,
      );
    }
    if (
      !input || ![
        "create",
        "update",
        "reset_password",
        "complete_password_change",
      ].includes(input.action)
    ) {
      return response({ error: "Acción no válida." }, 400);
    }

    const actorId = authData.user.id;
    const { data: actor, error: actorError } = await adminClient
      .from("usuarios")
      .select("rol, activo")
      .eq("id", actorId)
      .maybeSingle();
    if (actorError) throw actorError;
    if (actor?.activo !== true) {
      return response({ error: "La cuenta no está activa." }, 403);
    }
    if (input.action === "complete_password_change") {
      const password = readPassword(input.password);
      if (!password) {
        return response({
          error:
            "Indica una contraseña de al menos 8 caracteres y hasta 72 bytes.",
        }, 400);
      }
      if (authData.user.app_metadata.must_change_password !== true) {
        return response({ id: actorId });
      }
      const updatedPassword = await fetch(
        new URL("/auth/v1/user", supabaseUrl),
        {
          method: "PUT",
          headers: {
            apikey: anonKey,
            Authorization: authorization,
            "Content-Type": "application/json",
            "X-Supabase-Api-Version": "2024-01-01",
          },
          body: JSON.stringify({ password }),
          signal: AbortSignal.timeout(8000),
        },
      );
      if (!updatedPassword.ok) {
        const details = await updatedPassword.json().catch(() => null);
        const code = details?.code ?? details?.error_code;
        const message = code === "same_password"
          ? "La contraseña nueva debe ser diferente de la anterior."
          : code === "reauthentication_needed"
          ? "Vuelve a iniciar sesión antes de cambiar la contraseña."
          : "Supabase rechazó la nueva contraseña. Revisa sus requisitos.";
        return response({ error: message }, 400);
      }
      await updatedPassword.body?.cancel();
      const { error } = await adminClient.auth.admin.updateUserById(actorId, {
        app_metadata: { must_change_password: false },
        user_metadata: { must_change_password: false },
      });
      if (error) {
        return response(
          {
            error:
              "La contraseña se actualizó, pero falta confirmar el acceso. Si vuelve a aparecer este paso, elige otra contraseña para reintentar.",
          },
          502,
        );
      }
      return response({ id: actorId });
    }
    if (
      actor.rol !== "ADMINISTRADOR" ||
      authData.user.app_metadata.must_change_password === true
    ) {
      return response(
        {
          error:
            "Solo un administrador activo con acceso confirmado puede gestionar cuentas.",
        },
        403,
      );
    }

    async function recordAccountMovement(action: string, accountId: string) {
      try {
        const { error } = await adminClient.from("auditoria_movimientos")
          .insert({
            actor_id: actorId,
            actor_rol: "ADMINISTRADOR",
            accion: action,
            entidad: "usuarios",
            entidad_id: accountId,
          });
        if (error) {
          console.warn(
            "No se pudo guardar el movimiento de cuenta",
            error.code,
          );
        }
      } catch {
        console.warn("No se pudo guardar el movimiento de cuenta");
      }
    }

    if (input.action === "create") {
      const profile = readProfile(input);
      if (!staffRoles.has(profile.rol)) {
        return response({
          error: "Solo puedes crear cuentas de personal operativo.",
        }, 403);
      }
      const password = readPassword(input.password);
      if (!password) {
        return response({
          error:
            "Indica una contraseña de al menos 8 caracteres y hasta 72 bytes.",
        }, 400);
      }
      const { data, error } = await adminClient.auth.admin.createUser({
        email: profile.correo,
        password,
        email_confirm: true,
        app_metadata: { must_change_password: requirePasswordChange },
      });
      if (
        error?.code === "email_exists" || error?.code === "user_already_exists"
      ) {
        return response({ error: "Ya existe una cuenta con ese correo." }, 409);
      }
      if (error || !data.user) {
        if (error) {
          console.error("Supabase rechazó el alta de la cuenta", error.code);
        }
        return response(
          { error: "No se pudo crear la cuenta en Supabase." },
          502,
        );
      }

      // Some projects create the profile in a trigger when Auth creates the user.
      const { error: profileError } = await adminClient.from("usuarios").upsert(
        { id: data.user.id, ...profile },
        { onConflict: "id" },
      );
      if (profileError) {
        const { error: cleanupError } = await adminClient.auth.admin.deleteUser(
          data.user.id,
        );
        if (cleanupError) {
          console.error(
            "No se pudo revertir el alta incompleta",
            cleanupError.code,
          );
          return response({
            error:
              "El alta quedó incompleta. Revisa la cuenta en Supabase antes de volver a crearla.",
          }, 500);
        }
        console.error(
          "No se pudo guardar el perfil de la cuenta",
          profileError.code,
        );
        if (profileError.code === "PGRST204" || profileError.code === "42703") {
          return response({
            error: "Falta actualizar los perfiles de empleados en Supabase.",
          }, 503);
        }
        if (profileError.code === "23505") {
          return response(
            { error: "Ya existe un perfil con esos datos." },
            409,
          );
        }
        return response(
          { error: "No se pudo guardar el perfil de la cuenta." },
          500,
        );
      }
      await recordAccountMovement("Crear usuario", data.user.id);
      return response({ id: data.user.id });
    }

    const id = requiredString(input.id, "El usuario");
    const { data: target, error: targetError } = await adminClient
      .from("usuarios")
      .select("rol, activo, correo")
      .eq("id", id)
      .maybeSingle();
    if (targetError) throw targetError;
    if (!target) return response({ error: "No se encontró el usuario." }, 404);

    const editingOwnAccount = input.action === "update" && id === actorId;
    if (!editingOwnAccount && !staffRoles.has(target.rol)) {
      return response({
        error: "Tu rol no permite gestionar el acceso de esta cuenta.",
      }, 403);
    }
    if (input.action === "reset_password") {
      const password = readPassword(input.password);
      if (!password) {
        return response({
          error:
            "Indica una contraseña de al menos 8 caracteres y hasta 72 bytes.",
        }, 400);
      }
      const { error } = await adminClient.auth.admin.updateUserById(id, {
        password,
        app_metadata: { must_change_password: requirePasswordChange },
      });
      if (error) {
        console.warn("Supabase rechazó el restablecimiento", error.code);
        const invalid = error.status === 400 || error.status === 422;
        return response(
          {
            error: invalid
              ? "Supabase rechazó la contraseña. Revisa los requisitos de seguridad."
              : "Supabase no confirmó el cambio de contraseña.",
          },
          invalid ? 400 : 502,
        );
      }
      await recordAccountMovement("Cambiar contraseña de usuario", id);
      return response({ id });
    }

    const { data: targetAuth, error: targetAuthError } = await adminClient.auth
      .admin.getUserById(id);
    if (targetAuthError || !targetAuth.user) {
      return response(
        { error: "No se encontró la cuenta en Supabase Auth." },
        404,
      );
    }
    const oldEmail = targetAuth.user.email?.toLowerCase();
    if (!oldEmail || oldEmail !== target.correo?.trim().toLowerCase()) {
      return response({
        error:
          "El correo del perfil difiere del de autenticación. Revisa la cuenta en Supabase.",
      }, 409);
    }

    const profile = readProfile(input);
    const canSetRole = editingOwnAccount
      ? profile.rol === actor.rol && profile.activo
      : staffRoles.has(profile.rol);
    if (!canSetRole) {
      return response({
        error: "Tu rol no permite asignar ese puesto o estado.",
      }, 403);
    }
    const emailChanged = oldEmail !== profile.correo;
    if (emailChanged) {
      const { error } = await adminClient.auth.admin.updateUserById(id, {
        email: profile.correo,
        email_confirm: true,
      });
      if (error) {
        return response({
          error:
            "Supabase rechazó el cambio de correo. Verifica que esté disponible.",
        }, 409);
      }
    }

    const { data: updated, error: profileError } = await adminClient
      .from("usuarios")
      .update(profile)
      .eq("id", id)
      .eq("rol", target.rol)
      .eq("activo", target.activo)
      .eq("correo", target.correo)
      .select("id")
      .maybeSingle();
    if (profileError || !updated) {
      if (emailChanged) {
        const { error } = await adminClient.auth.admin.updateUserById(id, {
          email: oldEmail,
          email_confirm: true,
        });
        if (error) {
          console.error("No se pudo revertir el cambio de correo", error.code);
          return response({
            error:
              "No se pudo verificar el correo final. Revisa la cuenta en Supabase.",
          }, 500);
        }
      }
      return response({
        error:
          "El perfil no se pudo actualizar. Recarga la lista e inténtalo de nuevo.",
      }, 409);
    }

    if (target.rol !== profile.rol) {
      await recordAccountMovement("Cambiar rol de usuario", id);
    }
    if (target.activo !== profile.activo) {
      await recordAccountMovement(
        profile.activo ? "Activar usuario" : "Desactivar usuario",
        id,
      );
    }
    return response({ id });
  } catch (error) {
    if (error instanceof Error && error.message.endsWith("no es válido.")) {
      return response({ error: error.message }, 400);
    }
    if (
      error instanceof Error &&
      error.message === "Revisa los correos y el estado laboral."
    ) {
      return response({ error: error.message }, 400);
    }
    console.error("No se pudo completar una operación de manage-staff");
    return response(
      { error: "No se pudo completar la operación de cuenta." },
      500,
    );
  }
}

Deno.serve(handleRequest);
