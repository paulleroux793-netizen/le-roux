import React, { useState, useEffect, useRef, useCallback } from 'react'
import { X, ZoomIn, ZoomOut, RotateCcw, Sun, Contrast, Loader2 } from 'lucide-react'

// Full diagnostic DICOM viewer — renders the raw .dcm server-side with adjustable
// window/level (brightness/contrast), invert, zoom + pan. Opens over the patient file.
export default function DicomViewer({ study, onClose }) {
  const [imgUrl, setImgUrl] = useState(null)
  const [wc, setWc] = useState(null)
  const [ww, setWw] = useState(null)
  const [baseWc, setBaseWc] = useState(null)
  const [baseWw, setBaseWw] = useState(null)
  const [invert, setInvert] = useState(false)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(false)
  const [zoom, setZoom] = useState(1)
  const [pan, setPan] = useState({ x: 0, y: 0 })
  const dragRef = useRef(null)
  const reqRef = useRef(0)

  const fetchImage = useCallback(async (rwc, rww, rinv) => {
    const myReq = ++reqRef.current
    setLoading(true)
    try {
      const p = new URLSearchParams()
      if (rwc != null) p.set('wc', Math.round(rwc))
      if (rww != null) p.set('ww', Math.round(rww))
      if (rinv) p.set('invert', '1')
      const res = await fetch(`/imaging/${study.id}/dicom?${p.toString()}`)
      if (!res.ok) { if (myReq === reqRef.current) { setError(true); setLoading(false) } return }
      const dwc = parseFloat(res.headers.get('X-Window-Center'))
      const dww = parseFloat(res.headers.get('X-Window-Width'))
      const blob = await res.blob()
      if (myReq !== reqRef.current) return
      const url = URL.createObjectURL(blob)
      setImgUrl((old) => { if (old) URL.revokeObjectURL(old); return url })
      if (rwc == null && !isNaN(dwc)) { setWc(dwc); setBaseWc(dwc) }
      if (rww == null && !isNaN(dww)) { setWw(dww); setBaseWw(dww) }
      setError(false); setLoading(false)
    } catch (e) {
      if (myReq === reqRef.current) { setError(true); setLoading(false) }
    }
  }, [study.id])

  useEffect(() => { fetchImage(null, null, false) }, [fetchImage])

  useEffect(() => {
    if (baseWc == null) return
    const t = setTimeout(() => fetchImage(wc, ww, invert), 130)
    return () => clearTimeout(t)
  }, [wc, ww, invert, baseWc, fetchImage])

  useEffect(() => {
    const onKey = (e) => { if (e.key === 'Escape') onClose() }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [onClose])

  const reset = () => { setWc(baseWc); setWw(baseWw); setInvert(false); setZoom(1); setPan({ x: 0, y: 0 }) }
  const onWheel = (e) => { e.preventDefault(); setZoom((z) => Math.min(8, Math.max(0.4, z * (e.deltaY < 0 ? 1.15 : 0.87)))) }
  const onMouseDown = (e) => { dragRef.current = { x: e.clientX - pan.x, y: e.clientY - pan.y } }
  const onMouseMove = (e) => { if (dragRef.current) setPan({ x: e.clientX - dragRef.current.x, y: e.clientY - dragRef.current.y }) }
  const onMouseUp = () => { dragRef.current = null }

  return (
    <div className="fixed inset-0 z-50 flex flex-col bg-black/95" onMouseUp={onMouseUp} onMouseLeave={onMouseUp}>
      <div className="flex items-center justify-between gap-3 border-b border-white/10 px-4 py-2 text-white">
        <div className="text-sm">
          <span className="font-medium">{study.modality_label || 'Scan'}</span>
          {study.captured_at && <span className="ml-2 text-white/60">{new Date(study.captured_at).toLocaleDateString('en-ZA', { day: 'numeric', month: 'short', year: 'numeric' })}</span>}
          <span className="ml-2 text-white/40">{study.sidexis_patient_name}</span>
        </div>
        <button onClick={onClose} className="rounded p-1.5 hover:bg-white/10" title="Close (Esc)"><X className="h-5 w-5" /></button>
      </div>

      <div className="relative flex-1 overflow-hidden" onWheel={onWheel} onMouseDown={onMouseDown} onMouseMove={onMouseMove}
           style={{ cursor: dragRef.current ? 'grabbing' : 'grab' }}>
        {loading && <div className="absolute left-1/2 top-1/2 z-10 -translate-x-1/2 -translate-y-1/2 text-white/70"><Loader2 className="h-8 w-8 animate-spin" /></div>}
        {error ? (
          <div className="flex h-full items-center justify-center px-6 text-center text-white/70">
            No diagnostic DICOM for this study — it may be a clinical photo. The preview is still on the patient file.
          </div>
        ) : imgUrl && (
          <img src={imgUrl} alt="DICOM" draggable={false}
               className="absolute left-1/2 top-1/2 max-w-none select-none"
               style={{ transform: `translate(-50%,-50%) translate(${pan.x}px,${pan.y}px) scale(${zoom})` }} />
        )}
      </div>

      <div className="border-t border-white/10 bg-black/80 px-4 py-3 text-white">
        <div className="mx-auto flex max-w-3xl flex-wrap items-center justify-center gap-x-6 gap-y-2 text-xs">
          <label className="flex items-center gap-2"><Sun className="h-4 w-4" />Brightness
            <input type="range" min={Math.round((baseWc ?? 128) - (baseWw ?? 256))} max={Math.round((baseWc ?? 128) + (baseWw ?? 256))}
                   value={wc ?? 128} onChange={(e) => setWc(parseFloat(e.target.value))} className="w-32 accent-sky-400" disabled={baseWc == null} />
          </label>
          <label className="flex items-center gap-2"><Contrast className="h-4 w-4" />Contrast
            <input type="range" min={1} max={Math.round((baseWw ?? 256) * 3)} value={ww ?? 256}
                   onChange={(e) => setWw(parseFloat(e.target.value))} className="w-32 accent-sky-400" disabled={baseWc == null} />
          </label>
          <button onClick={() => setInvert((v) => !v)} className={`rounded px-2 py-1 ${invert ? 'bg-white/25' : 'hover:bg-white/10'}`}>Invert</button>
          <div className="flex items-center gap-1">
            <button onClick={() => setZoom((z) => Math.max(0.4, z * 0.8))} className="rounded p-1 hover:bg-white/10"><ZoomOut className="h-4 w-4" /></button>
            <span className="w-10 text-center text-white/50">{Math.round(zoom * 100)}%</span>
            <button onClick={() => setZoom((z) => Math.min(8, z * 1.25))} className="rounded p-1 hover:bg-white/10"><ZoomIn className="h-4 w-4" /></button>
          </div>
          <button onClick={reset} className="flex items-center gap-1 rounded px-2 py-1 hover:bg-white/10"><RotateCcw className="h-4 w-4" />Reset</button>
        </div>
        <div className="mt-1 text-center text-[10px] text-white/30">Scroll to zoom · drag to pan · for full SIDEXIS tools open SIDEXIS</div>
      </div>
    </div>
  )
}
