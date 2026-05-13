"use client"

import { useEffect, useState } from "react"
import { getHealth, getAnalytics, getUser, logout } from "@/lib/api"
import { useRouter } from "next/navigation"

export default function DashboardPage() {
  const router = useRouter()
  const [user, setUser] = useState<any>(null)
  const [health, setHealth] = useState<any>(null)
  const [analytics, setAnalytics] = useState<any>(null)

  useEffect(() => {
    const u = getUser()
    if (!u) { router.replace("/login"); return }
    setUser(u)
    Promise.all([
      getHealth().then(setHealth).catch(() => {}),
      getAnalytics().then(setAnalytics).catch(() => {}),
    ])
  }, [router])

  if (!user) return null

  return (
    <div className="flex min-h-screen">
      <nav className="w-56 bg-stone-900 text-stone-300 p-4 space-y-1 flex flex-col">
        <div className="text-white font-bold text-lg mb-4">CloseTalk</div>
        <a href="/dashboard" className="block px-3 py-2 rounded bg-stone-700 text-white text-sm">Dashboard</a>
        <a href="/users" className="block px-3 py-2 rounded hover:bg-stone-800 text-sm">Users</a>
        <a href="/reports" className="block px-3 py-2 rounded hover:bg-stone-800 text-sm">Reports</a>
        <a href="/flags" className="block px-3 py-2 rounded hover:bg-stone-800 text-sm">Feature Flags</a>
        <a href="/audit" className="block px-3 py-2 rounded hover:bg-stone-800 text-sm">Audit Log</a>
        <div className="flex-1" />
        <div className="text-xs text-stone-500 px-3">{user.display_name || user.email}</div>
        <button onClick={logout} className="text-left px-3 py-2 text-sm text-stone-400 hover:text-white">Logout</button>
      </nav>
      <main className="flex-1 p-6 space-y-6">
        <h1 className="text-2xl font-bold">Dashboard</h1>

        <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
          <div className="bg-white rounded-xl border p-5">
            <div className="text-sm text-stone-500">Total Users</div>
            <div className="text-3xl font-bold mt-1">{analytics?.total_users ?? "—"}</div>
          </div>
          <div className="bg-white rounded-xl border p-5">
            <div className="text-sm text-stone-500">Active Today</div>
            <div className="text-3xl font-bold mt-1">{analytics?.active_today ?? "—"}</div>
          </div>
          <div className="bg-white rounded-xl border p-5">
            <div className="text-sm text-stone-500">Signups Today</div>
            <div className="text-3xl font-bold mt-1">{analytics?.signups_today ?? "—"}</div>
          </div>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          <div className="bg-white rounded-xl border p-5">
            <div className="text-sm font-semibold text-stone-600 mb-2">Auth Service</div>
            <ServiceBadge status={health?.auth?.status} />
            <div className="text-xs text-stone-400 mt-1">{health?.auth?.service}</div>
          </div>
          <div className="bg-white rounded-xl border p-5">
            <div className="text-sm font-semibold text-stone-600 mb-2">Message Service</div>
            <ServiceBadge status={health?.message?.status} />
            <div className="text-xs text-stone-400 mt-1">{health?.message?.service}</div>
          </div>
        </div>
      </main>
    </div>
  )
}

function ServiceBadge({ status }: { status: string }) {
  const color = status === "ok" ? "bg-green-100 text-green-700" : "bg-red-100 text-red-700"
  return <span className={`inline-block px-2 py-0.5 rounded text-xs font-medium ${color}`}>{status}</span>
}
