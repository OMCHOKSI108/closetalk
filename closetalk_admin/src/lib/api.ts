const API = () => process.env.NEXT_PUBLIC_API_URL || "http://localhost:8081"

function getToken(): string | null {
  if (typeof window === "undefined") return null
  return localStorage.getItem("admin_token")
}

async function fetchAPI(path: string, init?: RequestInit) {
  const token = getToken()
  const res = await fetch(`${API()}${path}`, {
    ...init,
    headers: {
      "Content-Type": "application/json",
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
      ...init?.headers,
    },
  })
  if (res.status === 401 || res.status === 403) {
    localStorage.removeItem("admin_token")
    localStorage.removeItem("admin_user")
    if (typeof window !== "undefined" && !window.location.pathname.includes("/login")) {
      window.location.href = "/login"
    }
  }
  return res
}

export async function login(email: string, password: string) {
  const res = await fetchAPI("/auth/login", {
    method: "POST",
    body: JSON.stringify({ email, password }),
  })
  if (!res.ok) {
    const err = await res.json()
    throw new Error(err.error || "login failed")
  }
  const data = await res.json()
  localStorage.setItem("admin_token", data.access_token)
  localStorage.setItem("admin_user", JSON.stringify(data.user))
  return data
}

export function logout() {
  localStorage.removeItem("admin_token")
  localStorage.removeItem("admin_user")
  window.location.href = "/login"
}

export function getUser() {
  if (typeof window === "undefined") return null
  const raw = localStorage.getItem("admin_user")
  return raw ? JSON.parse(raw) : null
}

export async function getHealth() {
  // Auth service serves /health. Message service has its own /health but via
  // CloudFront's path-based routing, /health always lands on auth-service.
  // For local dev (separate ports) the override env var can split them.
  const authBase = API()
  const msgBase = process.env.NEXT_PUBLIC_MSG_API_URL || API()
  const [authRes, msgRes] = await Promise.allSettled([
    fetch(`${authBase}/health`),
    fetch(`${msgBase}/health`),
  ])
  return {
    auth: authRes.status === "fulfilled" && authRes.value.ok
      ? await authRes.value.json()
      : { status: "unreachable", service: "auth-service" },
    message: msgRes.status === "fulfilled" && msgRes.value.ok
      ? await msgRes.value.json()
      : { status: "unreachable", service: "message-service" },
  }
}

export async function getAnalytics() {
  const res = await fetchAPI("/admin/analytics")
  if (!res.ok) throw new Error("failed to fetch analytics")
  return res.json()
}

export async function listUsers(query?: string) {
  const q = query ? `?q=${encodeURIComponent(query)}` : ""
  const res = await fetchAPI(`/admin/users${q}`)
  if (!res.ok) throw new Error("failed to list users")
  return res.json()
}

export async function toggleUser(userId: string) {
  const res = await fetchAPI(`/admin/users/${userId}/disable`, { method: "PUT" })
  if (!res.ok) throw new Error("failed to toggle user")
  return res.json()
}

export async function listFlags() {
  const res = await fetchAPI("/admin/flags")
  if (!res.ok) throw new Error("failed to list flags")
  return res.json()
}

export async function updateFlag(id: string, data: { enabled?: boolean; rollout_percent?: number }) {
  const res = await fetchAPI(`/admin/flags/${id}`, {
    method: "PUT",
    body: JSON.stringify(data),
  })
  if (!res.ok) throw new Error("failed to update flag")
  return res.json()
}

export async function getAuditLog() {
  const res = await fetchAPI("/admin/audit-log")
  if (!res.ok) throw new Error("failed to get audit log")
  return res.json()
}

export async function deleteUser(userId: string) {
  const res = await fetchAPI(`/admin/users/${userId}`, { method: "DELETE" })
  if (!res.ok) throw new Error("failed to delete user")
  return res.json()
}

export async function getUserDetail(userId: string) {
  const res = await fetchAPI(`/admin/users/${userId}`)
  if (!res.ok) throw new Error("failed to get user detail")
  return res.json()
}

export async function listReports() {
  const res = await fetchAPI("/moderation/queue")
  if (!res.ok) return { items: [] }
  return res.json()
}

export async function reviewReport(messageId: string, action: string) {
  const res = await fetchAPI(`/moderation/${messageId}/review`, {
    method: "POST",
    body: JSON.stringify({ action }),
  })
  if (!res.ok) throw new Error("failed to review report")
  return res.json()
}
