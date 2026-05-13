"use client"

import { useEffect, useState } from "react"
import { listFlags, updateFlag, getUser, logout } from "@/lib/api"
import { useRouter } from "next/navigation"

export default function FlagsPage() {
  const router = useRouter()
  const [user, setUser] = useState<any>(null)
  const [flags, setFlags] = useState<any[]>([])
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    const u = getUser()
    if (!u) { router.replace("/login"); return }
    setUser(u)
  }, [router])

  function load() {
    setLoading(true)
    listFlags().then(d => setFlags(d.flags || [])).catch(() => {}).finally(() => setLoading(false))
  }

  useEffect(() => { if (user) load() }, [user])

  async function handleToggle(flag: any) {
    try {
      const newEnabled = !flag.enabled
      await updateFlag(flag.id, { enabled: newEnabled })
      setFlags(prev => prev.map(f => f.id === flag.id ? { ...f, enabled: newEnabled } : f))
    } catch {}
  }

  async function handleRollout(flag: any, val: number) {
    try {
      await updateFlag(flag.id, { rollout_percent: val })
      setFlags(prev => prev.map(f => f.id === flag.id ? { ...f, rollout_percent: val } : f))
    } catch {}
  }

  if (!user) return null

  return (
    <div className="flex min-h-screen">
      <nav className="w-56 bg-stone-900 text-stone-300 p-4 space-y-1 flex flex-col">
        <div className="text-white font-bold text-lg mb-4">CloseTalk</div>
        <a href="/dashboard" className="block px-3 py-2 rounded hover:bg-stone-800 text-sm">Dashboard</a>
        <a href="/users" className="block px-3 py-2 rounded hover:bg-stone-800 text-sm">Users</a>
        <a href="/reports" className="block px-3 py-2 rounded hover:bg-stone-800 text-sm">Reports</a>
        <a href="/flags" className="block px-3 py-2 rounded bg-stone-700 text-white text-sm">Feature Flags</a>
        <a href="/audit" className="block px-3 py-2 rounded hover:bg-stone-800 text-sm">Audit Log</a>
        <div className="flex-1" />
        <div className="text-xs text-stone-500 px-3">{user.display_name || user.email}</div>
        <button onClick={logout} className="text-left px-3 py-2 text-sm text-stone-400 hover:text-white">Logout</button>
      </nav>
      <main className="flex-1 p-6 space-y-4">
        <h1 className="text-2xl font-bold">Feature Flags</h1>
        <button onClick={load} className="px-3 py-1.5 text-sm bg-stone-800 text-white rounded-lg hover:bg-stone-700">Refresh</button>
        {loading ? (
          <div className="text-stone-500 text-sm">Loading...</div>
        ) : flags.length === 0 ? (
          <div className="text-stone-500 text-sm">No feature flags configured.</div>
        ) : (
          <div className="bg-white rounded-xl border overflow-hidden">
            <table className="w-full text-sm">
              <thead>
                <tr className="bg-stone-50 text-left text-stone-600">
                  <th className="px-4 py-3 font-medium">Flag</th>
                  <th className="px-4 py-3 font-medium">Description</th>
                  <th className="px-4 py-3 font-medium">Enabled</th>
                  <th className="px-4 py-3 font-medium">Rollout %</th>
                </tr>
              </thead>
              <tbody>
                {flags.map(f => (
                  <tr key={f.id} className="border-t hover:bg-stone-50">
                    <td className="px-4 py-3 font-mono text-xs">{f.name}</td>
                    <td className="px-4 py-3 text-stone-500 max-w-xs truncate">{f.description || "—"}</td>
                    <td className="px-4 py-3">
                      <button onClick={() => handleToggle(f)}
                        className={`text-xs px-3 py-1 rounded ${f.enabled ? "bg-green-100 text-green-700" : "bg-stone-200 text-stone-500"}`}>
                        {f.enabled ? "ON" : "OFF"}
                      </button>
                    </td>
                    <td className="px-4 py-3">
                      <select value={f.rollout_percent} onChange={e => handleRollout(f, parseInt(e.target.value))}
                        className="text-xs border rounded px-2 py-1">
                        {[0, 10, 25, 50, 75, 100].map(p => (
                          <option key={p} value={p}>{p}%</option>
                        ))}
                      </select>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </main>
    </div>
  )
}
