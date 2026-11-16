import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const allowedRoles = new Set([
  "ADMINISTRADOR",
  "GERENTE",
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

function optionalString(value: unknown, label: string, maxLength: number): string {
  if (value === undefined) return "";
  if (typeof value !== "string" || value.trim().length > maxLength) {
    throw new Error(`${label} no es válido.`);
  }
  return value.trim();
}

async function sendEmail(to: string, subject: string, text: string) {
  const apiKey = Deno.env.get("RESEND_API_KEY");
  const from = Deno.env.get("EMAIL_FROM");
  if (!apiKey || !from) {
    throw new Error("Falta configurar RESEND_API_KEY o EMAIL_FROM.");
  }

  const result = await fetch("https://api.resend.com/emails", {
    method: "POST",
    signal: AbortSignal.timeout(8000),
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ from, to: [to], subject, text }),
  });
  if (!result.ok) {
    throw new Error(`El proveedor de correo rechazó el envío (${result.status}).`);
  }
}

Deno.serve(async (request) => {
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
      global: { headers: { Authorization: authorization } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: authData, error: authError } =
      await authClient.auth.getUser(token);
    if (authError || !authData.user) {
      return response({ error: "La sesión no es válida." }, 401);
    }

    const adminClient = createClient(supabaseUrl, serviceKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const input = (await request.json()) as StaffRequest;
    if (
      ![
        "create",
        "update",
        "reset_password",
        "complete_password_change",
      ].includes(input.action)
    ) {
      return response({ error: "Acción no válida." }, 400);
    }
    if (input.action === "complete_password_change") {
      const { error } = await adminClient.auth.admin.updateUserById(
        authData.user.id,
        {
          app_metadata: {
            ...authData.user.app_metadata,
            must_change_password: false,
          },
        },
      );
      if (error) throw error;
      return response({ id: authData.user.id });
    }

    const { data: actor, error: actorError } = await adminClient
      .from("usuarios")
      .select("rol, activo")
      .eq("id", authData.user.id)
      .maybeSingle();
    if (actorError) throw actorError;
    if (actor?.rol !== "ADMINISTRADOR" || actor.activo !== true) {
      return response(
        { error: "Solo un administrador activo puede gestionar cuentas." },
        403,
      );
    }
    async function recordAccountMovement(action: string, accountId: string) {
      try {
        const { error } = await adminClient.from("auditoria_movimientos").insert({
          actor_id: authData.user!.id,
          actor_rol: "ADMINISTRADOR",
          accion: action,
          entidad: "usuarios",
          entidad_id: accountId,
        });
        if (error) console.warn("No se pudo guardar el movimiento de cuenta", error.code);
      } catch {
        console.warn("No se pudo guardar el movimiento de cuenta");
      }
    }

    if (input.action === "create") {
      const name = requiredString(input.name, "El nombre");
      const email = requiredString(input.email, "El correo").toLowerCase();
      const role = requiredString(input.role, "El rol");
      const password = requiredString(input.password, "La contraseña", 8);
      const employmentStatus = input.employmentStatus ?? "ACTIVO";
      const personalEmail = optionalString(
        input.personalEmail,
        "El correo personal",
        254,
      );
      const emailPattern = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;
      if (
        !emailPattern.test(email) ||
        !allowedRoles.has(role) ||
        !employmentStatuses.has(employmentStatus) ||
        (personalEmail !== "" && !emailPattern.test(personalEmail))
      ) {
        return response({ error: "Revisa los correos, el puesto y el estado laboral." }, 400);
      }

      const profile = {
        nombre_completo: name,
        correo: email,
        rol: role,
        activo: employmentStatus !== "INACTIVO",
        estado_laboral: employmentStatus,
        documento_identidad: optionalString(
          input.documentId,
          "El documento",
          32,
        ),
        correo_personal: personalEmail,
        telefono: optionalString(input.phone, "El teléfono", 32),
        direccion: optionalString(input.address, "La dirección", 500),
        departamento: optionalString(input.department, "El departamento", 100),
      };
      const { data, error } = await adminClient.auth.admin.createUser({
        email,
        password,
        email_confirm: true,
        user_metadata: { must_change_password: true },
        app_metadata: { must_change_password: true },
      });
      if (error?.code === "email_exists" || error?.code === "user_already_exists") {
        return response({ error: "Ya existe una cuenta con ese correo." }, 409);
      }
      if (error) throw error;
      if (!data.user) throw new Error("No se pudo crear la cuenta.");

      // Some projects create the profile in a trigger when Auth creates the user.
      const { error: profileError } = await adminClient.from("usuarios").upsert(
        { id: data.user.id, ...profile },
        { onConflict: "id" },
      );
      if (profileError) {
        const { error: cleanupError } = await adminClient.auth.admin.deleteUser(data.user.id);
        if (cleanupError) {
          console.error("No se pudo revertir el alta incompleta", cleanupError.code);
          return response({ error: "El alta quedó incompleta. Revisa la cuenta en Supabase antes de volver a crearla." }, 500);
        }
        console.error("No se pudo guardar el perfil de la cuenta", profileError.code);
        if (profileError.code === "PGRST204" || profileError.code === "42703") {
          return response({ error: "Falta actualizar los perfiles de empleados en Supabase." }, 503);
        }
        if (profileError.code === "23505") {
          return response({ error: "Ya existe un perfil con esos datos." }, 409);
        }
        return response({ error: "No se pudo guardar el perfil de la cuenta." }, 500);
      }
      await recordAccountMovement("Crear usuario", data.user.id);
      let emailSent = false;
      try {
        await sendEmail(
          email,
          "Tu acceso a Luxury",
          `Hola ${name},\n\nTu cuenta de Luxury está lista.\nCorreo: ${email}\nContraseña temporal: ${password}\n\nInicia sesión y cambia la contraseña temporal al ingresar.`,
        );
        emailSent = true;
      } catch (error) {
        console.warn("No se confirmó el correo de bienvenida", error instanceof Error ? error.message : "Error de envío");
      }
      return response({ id: data.user.id, emailSent });
    }

    const id = requiredString(input.id, "El usuario");
    const { data: target, error: targetError } = await adminClient
      .from("usuarios")
      .select("nombre_completo, correo")
      .eq("id", id)
      .maybeSingle();
    if (targetError) throw targetError;
    if (!target) return response({ error: "No se encontró el usuario." }, 404);

    if (input.action === "update") {
      const name = requiredString(input.name, "El nombre");
      const email = requiredString(input.email, "El correo").toLowerCase();
      const role = requiredString(input.role, "El rol");
      const employmentStatus = input.employmentStatus ?? "ACTIVO";
      const personalEmail = optionalString(
        input.personalEmail,
        "El correo personal",
        254,
      );
      if (
        !email.includes("@") ||
        !allowedRoles.has(role) ||
        !employmentStatuses.has(employmentStatus) ||
        (personalEmail !== "" && !personalEmail.includes("@"))
      ) {
        return response({ error: "El correo o el rol no son válidos." }, 400);
      }
      if (id === authData.user.id && role !== "ADMINISTRADOR") {
        return response(
          { error: "No puedes quitarte el rol de administrador activo." },
          400,
        );
      }
      if (target && role !== "ADMINISTRADOR") {
        const { count, error: countError } = await adminClient
          .from("usuarios")
          .select("id", { count: "exact", head: true })
          .eq("rol", "ADMINISTRADOR")
          .eq("activo", true);
        if (countError) throw countError;
        const { data: currentTarget, error: currentTargetError } =
          await adminClient
            .from("usuarios")
            .select("rol, activo")
            .eq("id", id)
            .single();
        if (currentTargetError) throw currentTargetError;
        if (
          currentTarget.rol === "ADMINISTRADOR" &&
          currentTarget.activo === true &&
          (count ?? 0) <= 1
        ) {
          return response(
            { error: "Debe quedar al menos un administrador activo." },
            400,
          );
        }
      }
      const { data: currentTarget, error: currentTargetError } =
        await adminClient
          .from("usuarios")
          .select("rol, activo")
          .eq("id", id)
          .single();
      if (currentTargetError) throw currentTargetError;
      const nextActive = employmentStatus !== "INACTIVO";
      for (const protectedRole of ["ADMINISTRADOR", "GERENTE"]) {
        const { count, error: countError } = await adminClient
          .from("usuarios")
          .select("id", { count: "exact", head: true })
          .eq("rol", protectedRole)
          .eq("activo", true);
        if (countError) throw countError;
        const targetCurrentlyCounts =
          currentTarget.rol === protectedRole && currentTarget.activo === true;
        const targetWillCount = role === protectedRole && nextActive;
        if ((count ?? 0) - Number(targetCurrentlyCounts) + Number(targetWillCount) < 1) {
          return response(
            { error: `Debe quedar al menos un ${protectedRole.toLowerCase()} activo.` },
            400,
          );
        }
      }
      const { error: authUpdateError } =
        await adminClient.auth.admin.updateUserById(id, {
          email,
          email_confirm: true,
        });
      if (authUpdateError) throw authUpdateError;
      const { error: profileUpdateError } = await adminClient
        .from("usuarios")
        .update({
          nombre_completo: name,
          correo: email,
          rol: role,
          activo: nextActive,
          estado_laboral: employmentStatus,
          documento_identidad: optionalString(
            input.documentId,
            "El documento",
            32,
          ),
          correo_personal: personalEmail,
          telefono: optionalString(input.phone, "El teléfono", 32),
          direccion: optionalString(input.address, "La dirección", 500),
          departamento: optionalString(input.department, "El departamento", 100),
        })
        .eq("id", id);
      if (profileUpdateError) {
        await adminClient.auth.admin.updateUserById(id, {
          email: target.correo,
          email_confirm: true,
        });
        throw profileUpdateError;
      }
      if (currentTarget.rol !== role) {
        await recordAccountMovement("Cambiar rol de usuario", id);
      }
      if (currentTarget.activo !== nextActive) {
        await recordAccountMovement(nextActive ? "Activar usuario" : "Desactivar usuario", id);
      }
      if (email !== target.correo) {
        await sendEmail(
          email,
          "Tu correo de acceso a Luxury fue actualizado",
          `Hola ${name},\n\nTu correo de acceso ahora es ${email}.`,
        );
      }
      return response({ id });
    }

    const password = requiredString(input.password, "La contraseña", 8);
    const { data: targetAuth, error: targetAuthError } =
      await adminClient.auth.admin.getUserById(id);
    if (targetAuthError) throw targetAuthError;
    const { error: resetError } = await adminClient.auth.admin.updateUserById(
      id,
      {
        password,
        user_metadata: { must_change_password: true },
        app_metadata: {
          ...targetAuth.user.app_metadata,
          must_change_password: true,
        },
      },
    );
    if (resetError) throw resetError;
    await recordAccountMovement("Restablecer contraseña de usuario", id);
    await sendEmail(
      target.correo,
      "Contraseña temporal de Luxury",
      `Hola ${target.nombre_completo},\n\nUn administrador restableció tu contraseña.\nCorreo: ${target.correo}\nContraseña temporal: ${password}\n\nInicia sesión y cámbiala inmediatamente.`,
    );
    return response({ id });
  } catch (error) {
    console.error("manage-staff failed", error);
    return response(
      { error: error instanceof Error ? error.message : "Error inesperado." },
      400,
    );
  }
});
