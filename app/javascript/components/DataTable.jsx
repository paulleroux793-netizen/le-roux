import React, { useState, useMemo, useEffect } from 'react'
import {
  useReactTable,
  getCoreRowModel,
  getSortedRowModel,
  getFilteredRowModel,
  getPaginationRowModel,
  flexRender,
} from '@tanstack/react-table'
import {
  ArrowUpDown, ArrowUp, ArrowDown,
  Search, ChevronLeft, ChevronRight,
} from 'lucide-react'

// ── Shared headless DataTable ───────────────────────────────────────
// A thin wrapper around @tanstack/react-table that gives us:
//   - Sortable columns (click a header)
//   - Global search (fuzzy across all filterable cells)
//   - Slot for page-specific filters (status dropdown, date, etc.)
//   - Client-side pagination with prev/next + numeric buttons
//   - Empty state handling (no data vs no matches)
//
// Accepts a `filters` render-prop so each page can inject its own
// filter UI without this component learning about every possible
// field. The filter UI reads and writes to the `columnFilters` state
// we manage here.
//
// Deliberately white / minimal to match the Phase 9.6 design refs.

export default function DataTable({
  columns,
  data,
  globalFilterPlaceholder = 'Search…',
  initialSort = [],
  pageSize = 10,
  filters,           // optional render-prop: ({ columnFilters, setColumnFilter }) => ReactNode
  rightActions,      // optional render-prop: () => ReactNode — buttons next to search
  emptyMessage = 'No results',
  totalLabel,        // optional string shown below the table in the footer
}) {
  const [sorting, setSorting]               = useState(initialSort)
  const [globalFilter, setGlobalFilter]     = useState('')
  const [debouncedFilter, setDebouncedFilter] = useState('')
  const [columnFilters, setColumnFilters]   = useState([])
  const [pagination, setPagination]         = useState({ pageIndex: 0, pageSize })

  // Debounce the search input so typing doesn't re-filter on every
  // keystroke. 200ms is the sweet spot: feels instant, avoids re-layout
  // thrash for 1000+ rows.
  useEffect(() => {
    const t = setTimeout(() => setDebouncedFilter(globalFilter), 200)
    return () => clearTimeout(t)
  }, [globalFilter])

  // Any time the user changes a filter, reset to page 1 — otherwise
  // you can end up on "page 7 of 2 matching rows".
  useEffect(() => {
    setPagination((p) => ({ ...p, pageIndex: 0 }))
  }, [debouncedFilter, columnFilters])

  const table = useReactTable({
    data,
    columns,
    state: {
      sorting,
      globalFilter: debouncedFilter,
      columnFilters,
      pagination,
    },
    onSortingChange: setSorting,
    onGlobalFilterChange: setGlobalFilter,
    onColumnFiltersChange: setColumnFilters,
    onPaginationChange: setPagination,
    getCoreRowModel: getCoreRowModel(),
    getSortedRowModel: getSortedRowModel(),
    getFilteredRowModel: getFilteredRowModel(),
    getPaginationRowModel: getPaginationRowModel(),
    // Default global filter: case-insensitive substring across every
    // cell value. Any column can opt out with `enableGlobalFilter: false`.
    globalFilterFn: 'includesString',
  })

  // Helper for per-page filter UI — lets the parent read/write a
  // single column filter by id without touching tanstack's shape.
  const setColumnFilter = (id, value) => {
    setColumnFilters((prev) => {
      const rest = prev.filter((f) => f.id !== id)
      if (value === '' || value == null) return rest
      return [...rest, { id, value }]
    })
  }
  const getColumnFilter = (id) =>
    columnFilters.find((f) => f.id === id)?.value ?? ''

  const totalRows = table.getFilteredRowModel().rows.length
  const pageStart = pagination.pageIndex * pagination.pageSize + 1
  const pageEnd   = Math.min(pageStart + pagination.pageSize - 1, totalRows)

  return (
    <div className="overflow-hidden rounded-xl border border-brand-accent/75 bg-white shadow-[0_28px_70px_-52px_rgba(57,60,77,0.35)]">
      {/* ── Header: search + filters + actions ────────────────── */}
      <div className="flex flex-wrap items-center gap-3 border-b border-brand-accent/70 bg-gradient-to-br from-brand-surface/35 via-white to-white p-4">
        <div className="relative flex-1 min-w-[220px] max-w-sm">
          <Search
            size={14}
            className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-brand-muted"
          />
          <input
            type="text"
            value={globalFilter}
            onChange={(e) => setGlobalFilter(e.target.value)}
            placeholder={globalFilterPlaceholder}
            className="w-full rounded-2xl border border-brand-accent/80 bg-white pl-9 pr-3 py-2.5 text-sm text-brand-ink transition-colors focus:border-brand-primary focus:outline-none focus:ring-4 focus:ring-brand-accent/45"
          />
        </div>
        {filters && (
          <div className="flex items-center gap-2 flex-wrap">
            {filters({ setColumnFilter, getColumnFilter })}
          </div>
        )}
        <div className="ml-auto flex items-center gap-2">
          {rightActions && rightActions()}
        </div>
      </div>

      {/* ── Table ─────────────────────────────────────────────── */}
      <div className="overflow-x-auto">
        <table className="min-w-full">
          <thead>
            {table.getHeaderGroups().map((headerGroup) => (
              <tr key={headerGroup.id} className="border-b border-brand-accent/55 bg-white">
                {headerGroup.headers.map((header) => {
                  const canSort = header.column.getCanSort()
                  const sort = header.column.getIsSorted()
                  return (
                    <th
                      key={header.id}
                      className="whitespace-nowrap px-5 py-3 text-left text-[11px] font-semibold uppercase tracking-wide text-brand-muted"
                      style={{ width: header.getSize() !== 150 ? header.getSize() : undefined }}
                    >
                      {header.isPlaceholder ? null : (
                        <button
                          type="button"
                          onClick={canSort ? header.column.getToggleSortingHandler() : undefined}
                          className={`inline-flex items-center gap-1 ${
                            canSort ? 'cursor-pointer hover:text-brand-ink' : 'cursor-default'
                          }`}
                        >
                          {flexRender(header.column.columnDef.header, header.getContext())}
                          {canSort && (
                            sort === 'asc' ? <ArrowUp size={12} /> :
                            sort === 'desc' ? <ArrowDown size={12} /> :
                            <ArrowUpDown size={12} className="text-brand-accent" />
                          )}
                        </button>
                      )}
                    </th>
                  )
                })}
              </tr>
            ))}
          </thead>
          <tbody>
            {table.getRowModel().rows.length === 0 ? (
              <tr>
                <td colSpan={columns.length} className="px-5 py-16 text-center text-sm text-brand-muted">
                  {data.length === 0 ? emptyMessage : 'No rows match the current filters'}
                </td>
              </tr>
            ) : (
              table.getRowModel().rows.map((row) => (
                <tr
                  key={row.id}
                  className="border-b border-brand-accent/25 transition-colors hover:bg-brand-surface/28"
                >
                  {row.getVisibleCells().map((cell) => (
                    <td key={cell.id} className="whitespace-nowrap px-5 py-4 text-sm text-brand-ink">
                      {flexRender(cell.column.columnDef.cell, cell.getContext())}
                    </td>
                  ))}
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>

      {/* ── Footer: counts + pagination ───────────────────────── */}
      <div className="flex items-center justify-between gap-4 border-t border-brand-accent/70 bg-brand-surface/18 p-4 text-xs text-brand-muted">
        <div>
          {totalRows > 0 ? (
            <>
              Showing <span className="font-semibold text-brand-ink">{pageStart}</span>–
              <span className="font-semibold text-brand-ink">{pageEnd}</span> of{' '}
              <span className="font-semibold text-brand-ink">{totalRows}</span>
              {totalLabel && ` ${totalLabel}`}
            </>
          ) : (
            totalLabel && `0 ${totalLabel}`
          )}
        </div>

        <Pagination table={table} />
      </div>
    </div>
  )
}

// ── Pagination controls (shared) ──────────────────────────────────
function Pagination({ table }) {
  const pageCount    = table.getPageCount()
  const currentPage  = table.getState().pagination.pageIndex + 1
  if (pageCount <= 1) return null

  // Build a compact page list: [1 … current-1, current, current+1 … last]
  const pages = []
  const push = (p) => pages.push(p)
  push(1)
  for (let p = Math.max(2, currentPage - 1); p <= Math.min(pageCount - 1, currentPage + 1); p++) push(p)
  if (pageCount > 1) push(pageCount)
  const unique = [...new Set(pages)].sort((a, b) => a - b)
  const withEllipsis = []
  unique.forEach((p, i) => {
    if (i > 0 && p - unique[i - 1] > 1) withEllipsis.push('…')
    withEllipsis.push(p)
  })

  const btn =
    'inline-flex items-center justify-center w-8 h-8 rounded-md text-xs font-medium transition-colors'

  return (
    <div className="flex items-center gap-1">
      <button
        onClick={() => table.previousPage()}
        disabled={!table.getCanPreviousPage()}
        className={`${btn} border border-brand-accent bg-white text-brand-muted hover:bg-brand-surface/32 disabled:cursor-not-allowed disabled:opacity-40`}
        aria-label="Previous page"
      >
        <ChevronLeft size={14} />
      </button>

      {withEllipsis.map((p, i) =>
        p === '…' ? (
          <span key={`e-${i}`} className="px-1 text-brand-muted">…</span>
        ) : (
          <button
            key={p}
            onClick={() => table.setPageIndex(p - 1)}
            className={`${btn} ${
              p === currentPage
                ? 'bg-brand-primary text-white shadow-[0_18px_35px_-24px_rgba(49,100,222,0.95)]'
                : 'border border-brand-accent bg-white text-brand-muted hover:bg-brand-surface/32'
            }`}
          >
            {p}
          </button>
        )
      )}

      <button
        onClick={() => table.nextPage()}
        disabled={!table.getCanNextPage()}
        className={`${btn} border border-brand-accent bg-white text-brand-muted hover:bg-brand-surface/32 disabled:cursor-not-allowed disabled:opacity-40`}
        aria-label="Next page"
      >
        <ChevronRight size={14} />
      </button>
    </div>
  )
}
