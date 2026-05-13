"use client"

import { useEffect, useState } from "react"
import { listUsers, toggleUser, deleteUser, batchDeleteUsers, getUserDetail, getUser, logout } from "@/lib/api"
import { useRouter } from "next/navigation"

export default function UsersPage() {
  const router = useRouter()
  const [user, setUser] = useState<any>(null)
  const [users, setUsers] = useState<any[]>([])
  const [query, setQuery] = useState("")
  const [loading, setLoading] = useState(true)
  const [detail, setDetail] = useState<any>(null)
  const [selected, setSelected] = useState<Set<string>>(new Set())

  useEffect(() => {
    const u = getUser()
    if (!u) { router.replace("/login"); return }
    setUser(u)
  }, [router])

  function loadUsers(q?: string) {
    setLoading(true)
    setSelected(new Set())
    listUsers(q).then(d => setUsers(d.users)).catch(() => {}).finally(() => setLoading(false))
  }

  useEffect(() => { if (user) loadUsers() }, [user])

  function toggleSelect(id: string) {
    setSelected(prev => {
      const next = new Set(prev)
      if (next.has(id)) {
        next.delete(id)
      } else {
        next.add(id)
      }
      return next
    })
  }

  function toggleSelectAll() {
    if (selected.size === users.length) {
      setSelected(new Set())
    } else {
      setSelected(new Set(users.map(u => u.id)))
    }
  }

  async function handleToggle(id: string) {
    try {
      const result = await toggleUser(id)
      setUsers(prev => prev.map(u => u.id === id ? { ...u, is_active: result.is_active } : u))
    } catch {}
  }

  async function handleDelete(id: string, name: string) {
    if (!confirm(`Delete user "${name}"? This cannot be undone.`)) return
    try {
      await deleteUser(id)
      setUsers(prev => prev.filter(u => u.id !== id))
      setSelected(prev => { const n = new Set(prev); n.delete(id); return n })
    } catch {}
  }

  async function handleBatchDelete() {
    if (selected.size === 0) return
    if (!confirm(`Delete ${selected.size} selected users? This cannot be undone.`)) return
    try {
      await batchDeleteUsers(Array.from(selected))
      setUsers(prev => prev.filter(u => !selected.has(u.id)))
      setSelected(new Set())
    } catch {}
  }

  async function handleShowDetail(id: string) {
    try {
      const d = await getUserDetail(id)
      setDetail(d)
    } catch {}
  }

  function handleSearch(e: React.FormEvent) {
    e.preventDefault()
    loadUsers(query || undefined)
  }

  if (!user) return null

  return (
    <div className="flex min-h-screen">
      <nav className="w-56 bg-stone-900 text-stone-300 p-4 space-y-1 flex flex-col">
        <div className="text-white font-bold text-lg mb-4">CloseTalk</div>
        <a href="/dashboard" className="block px-3 py-2 rounded hover:bg-stone-800 text-sm">Dashboard</a>
        <a href="/users" className="block px-3 py-2 rounded bg-stone-700 text-white text-sm">Users</a>
        <a href="/reports" className="block px-3 py-2 rounded hover:bg-stone-800 text-sm">Reports</a>
        <a href="/flags" className="block px-3 py-2 rounded hover:bg-stone-800 text-sm">Feature Flags</a>
        <a href="/audit" className="block px-3 py-2 rounded hover:bg-stone-800 text-sm">Audit Log</a>
        <div className="flex-1" />
        <div className="text-xs text-stone-500 px-3">{user.display_name || user.email}</div>
        <button onClick={logout} className="text-left px-3 py-2 text-sm text-stone-400 hover:text-white">Logout</button>
      </nav>
      <main className="flex-1 p-6 space-y-4">
        <div className="flex items-center justify-between">
          <h1 className="text-2xl font-bold">Users</h1>
          {selected.size > 0 && (
            <div className="flex items-center gap-3">
              <span className="text-sm text-stone-500">{selected.size} selected</span>
              <button onClick={handleBatchDelete}
                className="px-3 py-1.5 text-sm bg-red-600 text-white rounded-lg hover:bg-red-700">
                Delete Selected
              </button>
              <button onClick={() => setSelected(new Set())}
                className="px-3 py-1.5 text-sm bg-stone-200 text-stone-700 rounded-lg hover:bg-stone-300">
                Clear
              </button>
            </div>
          )}
        </div>
        <form onSubmit={handleSearch} className="flex gap-2">
          <input type="text" value={query} onChange={e => setQuery(e.target.value)}
            placeholder="Search by name, email, or username..."
            className="flex-1 max-w-md px-3 py-2 border rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-stone-400" />
          <button type="submit" className="px-4 py-2 bg-stone-800 text-white rounded-lg text-sm hover:bg-stone-700">Search</button>
        </form>
        {loading ? (
          <div className="text-stone-500 text-sm">Loading...</div>
        ) : users.length === 0 ? (
          <div className="text-stone-500 text-sm">No users found.</div>
        ) : (
          <div className="bg-white rounded-xl border overflow-hidden">
            <table className="w-full text-sm">
              <thead>
                <tr className="bg-stone-50 text-left text-stone-600">
                  <th className="px-4 py-3 w-10">
                    <input type="checkbox"
                      checked={users.length > 0 && selected.size === users.length}
                      onChange={toggleSelectAll}
                      className="accent-stone-800" />
                  </th>
                  <th className="px-4 py-3 font-medium">Name</th>
                  <th className="px-4 py-3 font-medium">Email</th>
                  <th className="px-4 py-3 font-medium">Username</th>
                  <th className="px-4 py-3 font-medium">Status</th>
                  <th className="px-4 py-3 font-medium">Admin</th>
                  <th className="px-4 py-3 font-medium">Created</th>
                  <th className="px-4 py-3 font-medium">Actions</th>
                </tr>
              </thead>
              <tbody>
                {users.map(u => (
                  <tr key={u.id} className={`border-t hover:bg-stone-50 cursor-pointer ${selected.has(u.id) ? "bg-stone-100" : ""}`}
                    onClick={() => handleShowDetail(u.id)}>
                    <td className="px-4 py-3" onClick={e => e.stopPropagation()}>
                      <input type="checkbox"
                        checked={selected.has(u.id)}
                        onChange={() => toggleSelect(u.id)}
                        className="accent-stone-800" />
                    </td>
                    <td className="px-4 py-3">{u.display_name}</td>
                    <td className="px-4 py-3 text-stone-500">{u.email}</td>
                    <td className="px-4 py-3 text-stone-500">@{u.username}</td>
                    <td className="px-4 py-3">
                      <span className={`px-2 py-0.5 rounded text-xs font-medium ${u.is_active ? "bg-green-100 text-green-700" : "bg-red-100 text-red-700"}`}>
                        {u.is_active ? "Active" : "Disabled"}
                      </span>
                    </td>
                    <td className="px-4 py-3">{u.is_admin ? "Yes" : "No"}</td>
                    <td className="px-4 py-3 text-stone-500">{new Date(u.created_at).toLocaleDateString()}</td>
                    <td className="px-4 py-3 space-x-1" onClick={e => e.stopPropagation()}>
                      <button onClick={() => handleToggle(u.id)}
                        className="text-xs px-3 py-1 rounded bg-stone-200 hover:bg-stone-300">
                        {u.is_active ? "Disable" : "Enable"}
                      </button>
                      <button onClick={() => handleDelete(u.id, u.display_name || u.email)}
                        className="text-xs px-3 py-1 rounded bg-red-100 text-red-700 hover:bg-red-200">
                        Delete
                      </button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}

        {detail && (
          <div className="fixed inset-0 bg-black/40 flex items-center justify-center z-50" onClick={() => setDetail(null)}>
            <div className="bg-white rounded-xl p-6 max-w-md w-full mx-4 shadow-xl" onClick={e => e.stopPropagation()}>
              <div className="flex justify-between items-center mb-4">
                <h2 className="text-lg font-bold">{detail.display_name}</h2>
                <button onClick={() => setDetail(null)} className="text-stone-400 hover:text-stone-600 text-xl">&times;</button>
              </div>
              <div className="space-y-2 text-sm">
                <div className="flex justify-between"><span className="text-stone-500">Email</span><span>{detail.email}</span></div>
                <div className="flex justify-between"><span className="text-stone-500">Username</span><span>@{detail.username || "(none)"}</span></div>
                <div className="flex justify-between"><span className="text-stone-500">Status</span><span className={detail.is_active ? "text-green-600" : "text-red-600"}>{detail.is_active ? "Active" : "Disabled"}</span></div>
                <div className="flex justify-between"><span className="text-stone-500">Admin</span><span>{detail.is_admin ? "Yes" : "No"}</span></div>
                <div className="flex justify-between"><span className="text-stone-500">Devices</span><span>{detail.device_count}</span></div>
                <div className="flex justify-between"><span className="text-stone-500">Groups</span><span>{detail.group_count}</span></div>
                <div className="flex justify-between"><span className="text-stone-500">Conversations</span><span>{detail.conversation_count}</span></div>
                <div className="flex justify-between"><span className="text-stone-500">Last Seen</span><span>{detail.last_seen ? new Date(detail.last_seen).toLocaleString() : "Never"}</span></div>
                <div className="flex justify-between"><span className="text-stone-500">Created</span><span>{detail.created_at ? new Date(detail.created_at).toLocaleString() : "Unknown"}</span></div>
              </div>
            </div>
          </div>
        )}
      </main>
    </div>
  )
}
