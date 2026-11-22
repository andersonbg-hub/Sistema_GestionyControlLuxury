const staffId = "00000000-0000-4000-8000-000000000002";
const actorId = "00000000-0000-4000-8000-000000000001";
const staffEmail = "empleado@example.test";

function expect(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

Deno.test("manage-staff valida el alta, el cambio de contraseña y la jerarquía", async (t) => {
  Deno.env.set("SUPABASE_URL", "https://supabase.example.test");
  Deno.env.set("SUPABASE_ANON_KEY", "test-anon");
  Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "test-service");
  const serve = Deno.serve;
  Object.defineProperty(Deno, "serve", { value: () => {}, configurable: true });
  const { handleRequest } = await import("./index.ts");
  Object.defineProperty(Deno, "serve", { value: serve, configurable: true });

  let actorRole = "ADMINISTRADOR";
  let targetRole = "MESERO";
  let pending = false;
  let history: {
    route: string;
    method: string;
    body: Record<string, unknown>;
  }[] = [];
  const originalFetch = globalThis.fetch;

  globalThis.fetch = async (input, init) => {
    const request = new Request(input, init);
    const url = new URL(request.url);
    const { pathname: route } = url;
    const body = request.body ? await request.json() : {};
    const method = request.method;
    history.push({ route, method, body });
    const user = (id: string, email: string, change = false) => ({
      id,
      email,
      app_metadata: { must_change_password: change },
      user_metadata: {},
    });

    if (route === "/auth/v1/user" && method === "GET") {
      return Response.json(user(actorId, "admin@example.test", pending));
    }
    if (route === "/auth/v1/user" && method === "PUT") {
      expect(
        request.headers.get("Authorization") === "Bearer sesion-de-prueba",
        "El cambio de contraseña exige la sesión del propio usuario",
      );
      if (body.password === "MismaClaveAnterior12!") {
        return Response.json({ code: "same_password" }, { status: 422 });
      }
      return Response.json(user(actorId, "admin@example.test", true));
    }
    if (route === "/rest/v1/usuarios") {
      if (method === "POST") return Response.json([]);
      if (url.searchParams.get("id") === `eq.${actorId}`) {
        return Response.json([{ rol: actorRole, activo: true }]);
      }
      return Response.json([{
        rol: targetRole,
        activo: true,
        correo: staffEmail,
      }]);
    }
    if (route === `/auth/v1/admin/users/${staffId}` && method === "GET") {
      return Response.json(user(staffId, staffEmail));
    }
    if (route === "/auth/v1/admin/users" && method === "POST") {
      return Response.json(user(staffId, staffEmail, true));
    }
    if (route === `/auth/v1/admin/users/${actorId}` && method === "PUT") {
      return Response.json(user(actorId, "admin@example.test"));
    }
    if (route === `/auth/v1/admin/users/${staffId}` && method === "PUT") {
      return Response.json(user(staffId, staffEmail, true));
    }
    if (route === "/rest/v1/auditoria_movimientos") return Response.json({});
    throw new Error(`Solicitud inesperada ${method} ${route}`);
  };

  function invoke(body: Record<string, unknown>, authenticated = true) {
    history = [];
    return handleRequest(
      new Request("https://function.example.test", {
        method: "POST",
        headers: authenticated
          ? { Authorization: "Bearer sesion-de-prueba" }
          : {},
        body: JSON.stringify(body),
      }),
    );
  }

  try {
    await t.step(
      "una llamada sin sesión se rechaza antes de consultar la base",
      async () => {
        const response = await invoke(
          { action: "reset_password", id: staffId },
          false,
        );
        expect(
          response.status === 401 && history.length === 0,
          "Se esperaba 401 sin solicitudes a Supabase",
        );
      },
    );
    await t.step(
      "un mesero y un administrador pendiente no pueden gestionar accesos",
      async () => {
        actorRole = "MESERO";
        expect(
          (await invoke({ action: "reset_password", id: staffId })).status ===
            403,
          "Debe rechazar al mesero",
        );
        actorRole = "ADMINISTRADOR";
        pending = true;
        expect(
          (await invoke({ action: "reset_password", id: staffId })).status ===
            403,
          "Debe rechazar al administrador pendiente",
        );
        expect(
          history.length === 2,
          "Debe consultar solamente la identidad y su perfil",
        );
        pending = false;
      },
    );
    await t.step(
      "un administrador no puede cambiar claves de gerentes ni de otros administradores",
      async () => {
        for (const role of ["GERENTE", "ADMINISTRADOR"]) {
          targetRole = role;
          expect(
            (await invoke({ action: "reset_password", id: staffId })).status ===
              403,
            "Debe proteger al usuario por su rol",
          );
          expect(
            !history.some((entry) => entry.route.startsWith("/auth/v1/admin")),
            "No debe tocar Supabase Auth del perfil protegido",
          );
        }
        targetRole = "MESERO";
      },
    );
    await t.step(
      "el administrador cambia la contraseña y obliga al cambio siguiente",
      async () => {
        const password = "AsignadaTemporal12!";
        const response = await invoke({
          action: "reset_password",
          id: staffId,
          password,
        });
        const result = await response.json();
        const account = history.find((entry) =>
          entry.method === "PUT" && entry.route.endsWith(staffId)
        );
        expect(
          response.status === 200 && result.id === staffId,
          "Debe confirmar el cambio real",
        );
        expect(
          account?.body.password === password,
          "Debe aplicar la contraseña indicada por Administración",
        );
        expect(
          (account.body.app_metadata as Record<string, unknown>)
            .must_change_password === true,
          "El siguiente inicio debe exigir otra contraseña",
        );
        expect(
          Object.keys(result).length === 1,
          "La respuesta solo debe incluir el identificador",
        );
        expect(
          history.every((entry) =>
            !entry.route.includes("generate_link") && entry.route !== "/emails"
          ),
          "No debe generar ni enviar correo",
        );
      },
    );
    await t.step(
      "el alta usa la contraseña asignada y no envía un correo",
      async () => {
        const input = {
          action: "create",
          name: "Empleado de prueba",
          email: staffEmail,
          role: "MESERO",
          password: "AsignadaTemporal12!",
        };
        const response = await invoke(input);
        const result = await response.json();
        const creation = history.find((entry) =>
          entry.route === "/auth/v1/admin/users"
        );
        expect(
          response.status === 200 && result.id === staffId,
          "Debe confirmar el alta",
        );
        expect(
          creation?.body.password === input.password,
          "Debe usar la contraseña indicada",
        );
        expect(
          (creation.body.app_metadata as Record<string, unknown>)
            .must_change_password === true,
          "El primer inicio debe exigir otra contraseña",
        );
        expect(
          Object.keys(result).length === 1,
          "La respuesta no debe traer una contraseña",
        );
        expect(
          history.every((entry) => entry.route !== "/emails"),
          "No debe enviar correo",
        );
        const missing = await invoke({ ...input, password: "" });
        expect(missing.status === 400, "Una contraseña vacía debe rechazarse");
      },
    );
    await t.step(
      "la marca de cambio obligatorio se limpia con la contraseña del propio usuario",
      async () => {
        pending = true;
        const skipped = await invoke({ action: "complete_password_change" });
        expect(
          skipped.status === 400 &&
            !history.some((entry) => entry.method === "PUT"),
          "La marca solo se limpia cuando se guarda la nueva contraseña",
        );
        const unchanged = await invoke({
          action: "complete_password_change",
          password: "MismaClaveAnterior12!",
        });
        expect(
          unchanged.status === 400 &&
            !history.some((entry) => entry.route.startsWith("/auth/v1/admin")),
          "Debe conservar la marca si la contraseña es la misma",
        );
        const response = await invoke({
          action: "complete_password_change",
          password: "OtraClaveDePrueba12!",
        });
        const update = history.find((entry) =>
          entry.method === "PUT" && entry.route.startsWith("/auth/v1/admin")
        );
        expect(
          response.status === 200 && update !== undefined &&
            update.route.endsWith(actorId),
          "Solo debe cambiar su propia cuenta",
        );
        expect(
          (update.body.app_metadata as Record<string, unknown>)
            .must_change_password === false,
          "Debe retirar la marca al guardar",
        );
      },
    );
  } finally {
    globalThis.fetch = originalFetch;
  }
});
