"use client"

import { useEffect, useState } from "react"
import { getAuditLog, getUser, logout } from "@/lib/api"
import { useRouter } from "next/navigation"

export default function AuditPage() {
  const router = useRouter()
  const [user, setUser] = useState<any>(null)
  const [entries, setEntries] = useState<any[]>([])
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    const u = getUser()
    if (!u) { router.replace("/login"); return }
    setUser(u)
    getAuditLog().then(d => setEntries(d.entries)).catch(() => {}).finally(() => setLoading(false))
  }, [router])

  if (!user) return null

  return (
    <div className="flex min-h-screen">
      <nav className="w-56 bg-stone-900 text-stone-300 p-4 space-y-1 flex flex-col">
        <div className="text-white font-bold text-lg mb-4">CloseTalk</div>
        <a href="/dashboard" className="block px-3 py-2 rounded hover:bg-stone-800 text-sm">Dashboard</a>
        <a href="/users" className="block px-3 py-2 rounded hover:bg-stone-800 text-sm">Users</a>
        <a href="/audit" className="block px-3 py-2 rounded bg-stone-700 text-white text-sm">Audit Log</a>
        <div className="flex-1" />
        <div className="text-xs text-stone-500 px-3">{user.display_name || user.email}</div>
        <button onClick={logout} className="text-left px-3 py-2 text-sm text-stone-400 hover:text-white">Logout</button>
      </nav>
      <main className="flex-1 p-6 space-y-4">
        <h1 className="text-2xl font-bold">Audit Log</h1>
        {loading ? (
          <div className="text-stone-500 text-sm">Loading...</div>
        ) : entries.length === 0 ? (
          <div className="text-stone-500 text-sm">No audit entries.</div>
        ) : (
          <div className="bg-white rounded-xl border overflow-hidden">
            <table className="w-full text-sm">
              <thead>
                <tr className="bg-stone-50 text-left text-stone-600">
                  <th className="px-4 py-3 font-medium">Time</th>
                  <th className="px-4 py-3 font-medium">Admin</th>
                  <th className="px-4 py-3 font-medium">Action</th>
                  <th className="px-4 py-3 font-medium">Target</th>
                  <th className="px-4 py-3 font-medium">Details</th>
                </tr>
              </thead>
              <tbody>
                {entries.map((e: any) => (
                  <tr key={e.id} className="border-t hover:bg-stone-50">
                    <td className="px-4 py-3 text-stone-500 whitespace-nowrap">{new Date(e.created_at).toLocaleString()}</td>
                    <td className="px-4 py-3 font-mono text-xs">{e.admin_id?.slice(0, 8)}</td>
                    <td className="px-4 py-3">
                      <span className="px-2 py-0.5 rounded text-xs font-medium bg-blue-100 text-blue-700">{e.action}</span>
                    </td>
                    <td className="px-4 py-3 text-stone-500">{e.target_type} {e.target_id?.slice(0, 8)}</td>
                    <td className="px-4 py-3 text-stone-500 text-xs max-w-xs truncate">{e.details}</td>
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
