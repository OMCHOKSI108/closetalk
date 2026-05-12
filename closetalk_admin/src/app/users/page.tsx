"use client"

import { useEffect, useState } from "react"
import { listUsers, toggleUser, getUser, logout } from "@/lib/api"
import { useRouter } from "next/navigation"

export default function UsersPage() {
  const router = useRouter()
  const [user, setUser] = useState<any>(null)
  const [users, setUsers] = useState<any[]>([])
  const [query, setQuery] = useState("")
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    const u = getUser()
    if (!u) { router.replace("/login"); return }
    setUser(u)
  }, [router])

  function loadUsers(q?: string) {
    setLoading(true)
    listUsers(q).then(d => setUsers(d.users)).catch(() => {}).finally(() => setLoading(false))
  }

  useEffect(() => { if (user) loadUsers() }, [user])

  async function handleToggle(id: string) {
    try {
      const result = await toggleUser(id)
      setUsers(prev => prev.map(u => u.id === id ? { ...u, is_active: result.is_active } : u))
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
        <a href="/audit" className="block px-3 py-2 rounded hover:bg-stone-800 text-sm">Audit Log</a>
        <div className="flex-1" />
        <div className="text-xs text-stone-500 px-3">{user.display_name || user.email}</div>
        <button onClick={logout} className="text-left px-3 py-2 text-sm text-stone-400 hover:text-white">Logout</button>
      </nav>
      <main className="flex-1 p-6 space-y-4">
        <h1 className="text-2xl font-bold">Users</h1>
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
                  <tr key={u.id} className="border-t hover:bg-stone-50">
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
                    <td className="px-4 py-3">
                      <button onClick={() => handleToggle(u.id)}
                        className="text-xs px-3 py-1 rounded bg-stone-200 hover:bg-stone-300">
                        {u.is_active ? "Disable" : "Enable"}
                      </button>
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
