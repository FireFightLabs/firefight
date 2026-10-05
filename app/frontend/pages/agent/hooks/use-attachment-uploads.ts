import { useEffect, useRef, useState } from "react"

import { CHAT_ATTACHMENT_KINDS } from "@/lib/generated/constants"
import { csrfToken } from "@/lib/http"
import { agentChatAttachmentPath, agentChatAttachmentsPath } from "@/lib/routes"
import { fileSize } from "@/pages/agent/lib/file-size"
import type { AgentChatAttachment, AgentChatAttachmentRules } from "@/types/serializers"

export const UPLOAD_STATES = { UPLOADING: "uploading", READY: "ready", FAILED: "failed" } as const

export type UploadState = (typeof UPLOAD_STATES)[keyof typeof UPLOAD_STATES]

// A file in the composer, uploaded the moment it is added so sending never waits on it.
export interface ComposerAttachment {
  key: string
  name: string
  size: string
  previewUrl: string | null
  progress: number
  state: UploadState
  error: string | null
  note: string | null
  uploaded: AgentChatAttachment | null
}

const UNREADABLE_ANSWER = "Firefight could not take this file. Try again."

interface UploadResult {
  attachment: AgentChatAttachment | null
  error: string | null
}

// XMLHttpRequest rather than fetch, since only it reports how much of an upload has gone.
function uploadFile(file: File, onProgress: (share: number) => void, requests: Map<string, XMLHttpRequest>, key: string) {
  return new Promise<UploadResult>((resolve) => {
    const request = new XMLHttpRequest()
    requests.set(key, request)
    const body = new FormData()
    body.append("file", file)

    request.upload.onprogress = (event) => {
      if (event.lengthComputable) {
        onProgress(event.loaded / event.total)
      }
    }
    request.onload = () => {
      requests.delete(key)
      resolve(readAnswer(request))
    }
    request.onerror = () => {
      requests.delete(key)
      resolve({ attachment: null, error: UNREADABLE_ANSWER })
    }
    request.open("POST", agentChatAttachmentsPath())
    request.setRequestHeader("X-CSRF-Token", csrfToken())
    request.setRequestHeader("Accept", "application/json")
    request.send(body)
  })
}

// A refusal carries its own sentence. Anything that is not the answer we expect, such as a redirect for want of a
// permission, is said plainly.
function readAnswer(request: XMLHttpRequest): UploadResult {
  try {
    const answer = JSON.parse(request.responseText) as Partial<AgentChatAttachment> & { error?: string }
    if (request.status === 201 && answer.id) {
      return { attachment: answer as AgentChatAttachment, error: null }
    }
    return { attachment: null, error: answer.error ?? UNREADABLE_ANSWER }
  } catch {
    return { attachment: null, error: UNREADABLE_ANSWER }
  }
}

function forgetUpload(id: string) {
  void fetch(agentChatAttachmentPath(id), { method: "DELETE", headers: { "X-CSRF-Token": csrfToken() } })
}

let nextKey = 0

export function useAttachmentUploads(rules: AgentChatAttachmentRules) {
  const [ items, setItems ] = useState<ComposerAttachment[]>([])
  const [ notice, setNotice ] = useState<string | null>(null)
  const requests = useRef(new Map<string, XMLHttpRequest>())
  const previews = useRef(new Set<string>())

  // The browser holds each preview until it is let go, so they are let go when the page leaves.
  useEffect(() => {
    const held = previews.current
    const running = requests.current
    return () => {
      held.forEach((url) => URL.revokeObjectURL(url))
      running.forEach((request) => request.abort())
    }
  }, [])

  function change(key: string, update: Partial<ComposerAttachment>) {
    setItems((current) => current.map((item) => (item.key === key ? { ...item, ...update } : item)))
  }

  function preview(file: File) {
    if (!file.type.startsWith("image/")) {
      return null
    }
    const url = URL.createObjectURL(file)
    previews.current.add(url)
    return url
  }

  async function start(item: ComposerAttachment, file: File) {
    const result = await uploadFile(file, (share) => change(item.key, { progress: share }), requests.current, item.key)
    if (!result.attachment) {
      change(item.key, { state: UPLOAD_STATES.FAILED, error: result.error })
      return
    }

    const unseenImage = result.attachment.kind === CHAT_ATTACHMENT_KINDS.IMAGE ? rules.imagesUnread : null
    change(item.key, {
      state: UPLOAD_STATES.READY, progress: 1, size: result.attachment.size, note: unseenImage, uploaded: result.attachment,
    })
  }

  function add(files: File[]) {
    const room = rules.maxFiles - items.length
    setNotice(files.length > room ? rules.tooMany : null)

    const added = files.slice(0, Math.max(room, 0)).map((file) => {
      const tooLarge = file.size > rules.maxBytes
      const item: ComposerAttachment = {
        key: `upload-${nextKey++}`, name: file.name, size: fileSize(file.size), previewUrl: preview(file), progress: 0,
        state: tooLarge ? UPLOAD_STATES.FAILED : UPLOAD_STATES.UPLOADING,
        error: tooLarge ? `${file.name} is larger than ${rules.maxSize}, the most Halon reads.` : null, note: null, uploaded: null,
      }
      return { item, file, tooLarge }
    })

    setItems((current) => [ ...current, ...added.map((entry) => entry.item) ])
    added.filter((entry) => !entry.tooLarge).forEach((entry) => void start(entry.item, entry.file))
  }

  function remove(key: string) {
    const item = items.find((candidate) => candidate.key === key)
    requests.current.get(key)?.abort()
    if (item?.uploaded) {
      forgetUpload(item.uploaded.id)
    }
    if (item?.previewUrl) {
      URL.revokeObjectURL(item.previewUrl)
      previews.current.delete(item.previewUrl)
    }
    setNotice(null)
    setItems((current) => current.filter((candidate) => candidate.key !== key))
  }

  // Sent, so the server owns them now. Previews stay held until the page leaves, since the sent message shows them.
  function clear() {
    setNotice(null)
    setItems([])
  }

  const uploaded = items.flatMap((item) => (item.uploaded ? [ item.uploaded ] : []))
  const sendable = items.every((item) => item.state === UPLOAD_STATES.READY)
  const previewsById = Object.fromEntries(items.flatMap((item) => (item.uploaded && item.previewUrl ? [ [ item.uploaded.id, item.previewUrl ] ] : [])))

  return { items, notice, add, remove, clear, uploaded, sendable, previewsById }
}
