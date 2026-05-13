"use client"

import { useEffect, useState } from "react"
import { listReports, reviewReport, getUser, logout } from "@/lib/api"
import { useRouter } from "next/navigation"

export default function ReportsPage() {
  const router = useRouter()
  const [user, setUser] = useState<any>(null)
  const [items, setItems] = useState<any[]>([])
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    const u = getUser()
    if (!u) { router.replace("/login"); return }
    setUser(u)
  }, [router])

  function load() {
    setLoading(true)
    listReports().then(d => setItems(d.items || [])).catch(() => {}).finally(() => setLoading(false))
  }

  useEffect(() => { if (user) load() }, [user])

  async function handleReview(messageId: string, action: string) {
    try {
      await reviewReport(messageId, action)
      setItems(prev => prev.filter(i => i.message_id !== messageId))
    } catch {}
  }

  if (!user) return null

  return (
    <div className="flex min-h-screen">
      <nav className="w-56 bg-stone-900 text-stone-300 p-4 space-y-1 flex flex-col">
        <div className="text-white font-bold text-lg mb-4">CloseTalk</div>
        <a href="/dashboard" className="block px-3 py-2 rounded hover:bg-stone-800 text-sm">Dashboard</a>
        <a href="/users" className="block px-3 py-2 rounded hover:bg-stone-800 text-sm">Users</a>
        <a href="/reports" className="block px-3 py-2 rounded bg-stone-700 text-white text-sm">Reports</a>
        <a href="/flags" className="block px-3 py-2 rounded hover:bg-stone-800 text-sm">Feature Flags</a>
        <a href="/audit" className="block px-3 py-2 rounded hover:bg-stone-800 text-sm">Audit Log</a>
        <div className="flex-1" />
        <div className="text-xs text-stone-500 px-3">{user.display_name || user.email}</div>
        <button onClick={logout} className="text-left px-3 py-2 text-sm text-stone-400 hover:text-white">Logout</button>
      </nav>
      <main className="flex-1 p-6 space-y-4">
        <h1 className="text-2xl font-bold">Message Reports</h1>
        <button onClick={load} className="px-3 py-1.5 text-sm bg-stone-800 text-white rounded-lg hover:bg-stone-700">Refresh</button>
        {loading ? (
          <div className="text-stone-500 text-sm">Loading...</div>
        ) : items.length === 0 ? (
          <div className="text-stone-500 text-sm">No pending reports.</div>
        ) : (
          <div className="bg-white rounded-xl border overflow-hidden">
            <table className="w-full text-sm">
              <thead>
                <tr className="bg-stone-50 text-left text-stone-600">
                  <th className="px-4 py-3 font-medium">Message</th>
                  <th className="px-4 py-3 font-medium">Sender</th>
                  <th className="px-4 py-3 font-medium">Reason</th>
                  <th className="px-4 py-3 font-medium">Reported</th>
                  <th className="px-4 py-3 font-medium">Actions</th>
                </tr>
              </thead>
              <tbody>
                {items.map((i: any) => (
                  <tr key={i.message_id || i.id} className="border-t hover:bg-stone-50">
                    <td className="px-4 py-3 max-w-xs truncate">{i.content || i.message || "(no content)"}</td>
                    <td className="px-4 py-3 text-stone-500">{i.sender_name || i.sender_id?.slice(0, 8) || "—"}</td>
                    <td className="px-4 py-3"><span className="px-2 py-0.5 rounded text-xs font-medium bg-amber-100 text-amber-700">{i.reason || i.flag_reason || "flagged"}</span></td>
                    <td className="px-4 py-3 text-stone-500">{i.created_at ? new Date(i.created_at).toLocaleDateString() : "—"}</td>
                    <td className="px-4 py-3 space-x-1">
                      <button onClick={() => handleReview(i.message_id || i.id, "approve")}
                        className="text-xs px-3 py-1 rounded bg-green-100 text-green-700 hover:bg-green-200">Approve</button>
                      <button onClick={() => handleReview(i.message_id || i.id, "remove")}
                        className="text-xs px-3 py-1 rounded bg-red-100 text-red-700 hover:bg-red-200">Remove</button>
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
