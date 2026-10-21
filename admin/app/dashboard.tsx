"use client";

import {
  ChangeEvent,
  FormEvent,
  useEffect,
  useMemo,
  useRef,
  useState,
  useSyncExternalStore,
} from "react";
import { createClient, type Session, type SupabaseClient } from "@supabase/supabase-js";

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
const supabasePublishableKey =
  process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY ??
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
const supabase: SupabaseClient | null =
  supabaseUrl && supabasePublishableKey
    ? createClient(supabaseUrl, supabasePublishableKey)
    : null;

type Recording = {
  id: string;
  type: string;
  url?: string;
  durationSeconds?: number;
  fileSizeBytes?: number;
  attribution?: string;
  permission?: string;
};

type Hymn = {
  id: string;
  number: string;
  title: string;
  language: "english" | "twi";
  stanzas: string[];
  chorus?: string;
  author?: string;
  composer?: string;
  source?: string;
  copyright?: string;
  attribution?: string;
  permission?: string;
  artwork?: string;
  recordings?: Recording[];
};

type Catalogue = {
  schemaVersion: number;
  catalogueVersion?: string;
  hymns: Hymn[];
};

type HymnDraft = Omit<Hymn, "stanzas" | "recordings"> & {
  stanzasText: string;
  recordingsText: string;
};

type PdfImport = {
  id: string;
  original_filename: string;
  storage_path: string;
  extracted_text: string;
  page_count: number;
  created_at: string;
};

const STORAGE_KEY = "pcg-hymn-admin-draft";
const EMPTY_CATALOGUE = '{"schemaVersion":1,"hymns":[]}';
const CATALOGUE_CHANGE_EVENT = "pcg-hymn-catalogue-change";
const RECORDING_TYPES = [
  "maleSolo",
  "femaleSolo",
  "choir",
  "congregation",
  "instrumental",
];

function getCatalogueSnapshot() {
  return typeof window === "undefined"
    ? EMPTY_CATALOGUE
    : window.localStorage.getItem(STORAGE_KEY) ?? EMPTY_CATALOGUE;
}

function subscribeToCatalogue(onChange: () => void) {
  window.addEventListener("storage", onChange);
  window.addEventListener(CATALOGUE_CHANGE_EVENT, onChange);
  return () => {
    window.removeEventListener("storage", onChange);
    window.removeEventListener(CATALOGUE_CHANGE_EVENT, onChange);
  };
}

function validateCatalogue(value: unknown): Catalogue {
  if (
    !value ||
    typeof value !== "object" ||
    !("schemaVersion" in value) ||
    !("hymns" in value)
  ) {
    throw new Error("The file must contain schemaVersion and a hymns array.");
  }

  const candidate = value as Record<string, unknown>;
  if (candidate.schemaVersion !== 1 || !Array.isArray(candidate.hymns)) {
    throw new Error("Only schema version 1 catalogues are supported.");
  }
  if (
    candidate.catalogueVersion !== undefined &&
    typeof candidate.catalogueVersion !== "string"
  ) {
    throw new Error("catalogueVersion must be a string.");
  }

  const ids = new Set<string>();
  const recordingIds = new Set<string>();
  for (const [index, item] of candidate.hymns.entries()) {
    if (!item || typeof item !== "object" || Array.isArray(item)) {
      throw new Error(`Hymn ${index + 1} must be an object.`);
    }
    const hymn = item as Record<string, unknown>;
    for (const field of ["id", "number", "title"] as const) {
      if (typeof hymn[field] !== "string" || !hymn[field].trim()) {
        throw new Error(`Hymn ${index + 1} needs a non-empty ${field}.`);
      }
    }
    if (ids.has(hymn.id as string)) {
      throw new Error(`Duplicate hymn ID: ${hymn.id}`);
    }
    ids.add(hymn.id as string);
    if (hymn.language !== "english" && hymn.language !== "twi") {
      throw new Error(`Hymn "${hymn.title}" has an unsupported language.`);
    }
    for (const field of [
      "chorus",
      "author",
      "composer",
      "source",
      "copyright",
      "attribution",
      "permission",
      "artwork",
    ]) {
      if (hymn[field] !== undefined && typeof hymn[field] !== "string") {
        throw new Error(`Hymn "${hymn.title}" has an invalid ${field}.`);
      }
    }
    if (
      !Array.isArray(hymn.stanzas) ||
      hymn.stanzas.some((stanza) => typeof stanza !== "string")
    ) {
      throw new Error(`Hymn "${hymn.title}" needs an array of stanza strings.`);
    }
    if (hymn.recordings !== undefined && !Array.isArray(hymn.recordings)) {
      throw new Error(`Hymn "${hymn.title}" has malformed recordings.`);
    }
    for (const recording of (hymn.recordings ?? []) as unknown[]) {
      if (!recording || typeof recording !== "object" || Array.isArray(recording)) {
        throw new Error(`Hymn "${hymn.title}" has a malformed recording.`);
      }
      const audio = recording as Record<string, unknown>;
      if (
        typeof audio.id !== "string" ||
        !audio.id.trim() ||
        typeof audio.type !== "string" ||
        !RECORDING_TYPES.includes(audio.type)
      ) {
        throw new Error(`Hymn "${hymn.title}" has a recording with an invalid ID or type.`);
      }
      if (recordingIds.has(audio.id)) {
        throw new Error(`Duplicate recording ID: ${audio.id}`);
      }
      recordingIds.add(audio.id);
      if (audio.url !== undefined) {
        if (typeof audio.url !== "string") {
          throw new Error(`Recording "${audio.id}" must use a valid HTTPS URL.`);
        }
        if (audio.url) {
          try {
            const url = new URL(audio.url);
            if (url.protocol !== "https:") throw new Error();
          } catch {
            throw new Error(`Recording "${audio.id}" must use a valid HTTPS URL.`);
          }
        }
      }
      for (const field of ["attribution", "permission"] as const) {
        if (audio[field] !== undefined && typeof audio[field] !== "string") {
          throw new Error(`Recording "${audio.id}" has an invalid ${field}.`);
        }
      }
      for (const field of ["durationSeconds", "fileSizeBytes"] as const) {
        const value = audio[field];
        if (
          value !== undefined &&
          (typeof value !== "number" ||
            !Number.isInteger(value) ||
            value < 0)
        ) {
          throw new Error(`Recording "${audio.id}" has an invalid ${field}.`);
        }
      }
    }
  }

  return {
    schemaVersion: 1,
    ...(typeof candidate.catalogueVersion === "string"
      ? { catalogueVersion: candidate.catalogueVersion }
      : {}),
    hymns: candidate.hymns as Hymn[],
  };
}

function updateCatalogue(
  updater: Catalogue | ((current: Catalogue) => Catalogue),
) {
  const next =
    typeof updater === "function"
      ? updater(validateCatalogue(JSON.parse(getCatalogueSnapshot())))
      : validateCatalogue(updater);
  window.localStorage.setItem(STORAGE_KEY, JSON.stringify(next));
  window.dispatchEvent(new Event(CATALOGUE_CHANGE_EVENT));
}

function stableJson(value: unknown): string {
  if (Array.isArray(value)) {
    return `[${value.map(stableJson).join(",")}]`;
  }
  if (value && typeof value === "object") {
    return `{${Object.entries(value)
      .sort(([left], [right]) => left.localeCompare(right))
      .map(([key, entry]) => `${JSON.stringify(key)}:${stableJson(entry)}`)
      .join(",")}}`;
  }
  return JSON.stringify(value) ?? "null";
}

async function extractPdfText(file: File) {
  const pdfjs = await import("pdfjs-dist");
  pdfjs.GlobalWorkerOptions.workerSrc = new URL(
    "pdfjs-dist/build/pdf.worker.min.mjs",
    import.meta.url,
  ).toString();

  const loadingTask = pdfjs.getDocument({
    data: new Uint8Array(await file.arrayBuffer()),
  });
  const document = await loadingTask.promise;
  const pages: string[] = [];
  try {
    for (let pageNumber = 1; pageNumber <= document.numPages; pageNumber += 1) {
      const page = await document.getPage(pageNumber);
      const content = await page.getTextContent();
      const lines: string[] = [];
      let line = "";
      for (const item of content.items) {
        if (!("str" in item)) continue;
        line += item.str;
        if (item.hasEOL) {
          lines.push(line.trimEnd());
          line = "";
        } else {
          line += " ";
        }
      }
      if (line.trim()) lines.push(line.trimEnd());
      pages.push(lines.join("\n"));
    }
  } finally {
    await loadingTask.destroy();
  }
  const text = pages.join("\n\n").trim();
  if (!text) {
    throw new Error("No selectable text was found. Scanned PDFs need OCR and are not supported yet.");
  }
  return { text, pageCount: pages.length };
}

function emptyDraft(): HymnDraft {
  return {
    id: "",
    number: "",
    title: "",
    language: "english",
    stanzasText: "",
    recordingsText: "[]",
  };
}

function toDraft(hymn: Hymn): HymnDraft {
  const { stanzas, recordings = [], ...fields } = hymn;
  return {
    ...fields,
    stanzasText: stanzas.join("\n\n"),
    recordingsText: JSON.stringify(recordings, null, 2),
  };
}

function Icon({
  name,
  size = 20,
}: {
  name: "book" | "search" | "plus" | "upload" | "download" | "more" | "music";
  size?: number;
}) {
  const paths = {
    book: <><path d="M4 5.5A2.5 2.5 0 0 1 6.5 3H20v16H6.5A2.5 2.5 0 0 0 4 21.5z" /><path d="M4 5.5v16M8 7h8M8 11h8" /></>,
    search: <><circle cx="10.8" cy="10.8" r="6.3" /><path d="m16 16 4 4" /></>,
    plus: <><path d="M12 5v14M5 12h14" /></>,
    upload: <><path d="M12 16V4m0 0L7 9m5-5 5 5" /><path d="M5 14v5h14v-5" /></>,
    download: <><path d="M12 4v12m0 0 5-5m-5 5-5-5" /><path d="M5 19h14" /></>,
    more: <><circle cx="5" cy="12" r="1" /><circle cx="12" cy="12" r="1" /><circle cx="19" cy="12" r="1" /></>,
    music: <><path d="M9 18V5l12-2v13" /><circle cx="6" cy="18" r="3" /><circle cx="18" cy="16" r="3" /></>,
  };
  return (
    <svg
      aria-hidden="true"
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.7"
      strokeLinecap="round"
      strokeLinejoin="round"
    >
      {paths[name]}
    </svg>
  );
}

export default function CatalogueDashboard() {
  const catalogueSnapshot = useSyncExternalStore(
    subscribeToCatalogue,
    getCatalogueSnapshot,
    () => EMPTY_CATALOGUE,
  );
  const { catalogue, storageError } = useMemo(() => {
    try {
      return {
        catalogue: validateCatalogue(JSON.parse(catalogueSnapshot)),
        storageError: "",
      };
    } catch {
      return {
        catalogue: { schemaVersion: 1, hymns: [] } as Catalogue,
        storageError: "The saved browser draft is invalid. Import a valid catalogue to replace it.",
      };
    }
  }, [catalogueSnapshot]);
  const [query, setQuery] = useState("");
  const [language, setLanguage] = useState("all");
  const [draft, setDraft] = useState<HymnDraft | null>(null);
  const [editingId, setEditingId] = useState<string | null>(null);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");
  const [menuId, setMenuId] = useState<string | null>(null);
  const [session, setSession] = useState<Session | null>(null);
  const [authReady, setAuthReady] = useState(!supabase);
  const [isAdmin, setIsAdmin] = useState<boolean | null>(null);
  const [authError, setAuthError] = useState("");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [signingIn, setSigningIn] = useState(false);
  const [syncing, setSyncing] = useState(false);
  const [cloudChannel, setCloudChannel] = useState<"local" | "draft" | "published">("local");
  const [pdfImports, setPdfImports] = useState<PdfImport[]>([]);
  const [uploadingPdfs, setUploadingPdfs] = useState(false);
  const fileInput = useRef<HTMLInputElement>(null);
  const pdfInput = useRef<HTMLInputElement>(null);

  useEffect(() => {
    if (!supabase) return;
    let active = true;
    const { data } = supabase.auth.onAuthStateChange((_event, nextSession) => {
      if (active) {
        setSession(nextSession);
        setIsAdmin(null);
      }
    });
    void supabase.auth
      .getSession()
      .then(({ data: sessionData, error: sessionError }) => {
        if (!active) return;
        if (sessionError) setAuthError(sessionError.message);
        setSession(sessionData.session);
        setAuthReady(true);
      })
      .catch((reason: unknown) => {
        if (!active) return;
        setAuthError(
          `Could not read the sign-in session: ${reason instanceof Error ? reason.message : "unknown error"}`,
        );
        setAuthReady(true);
      });
    return () => {
      active = false;
      data.subscription.unsubscribe();
    };
  }, []);

  useEffect(() => {
    if (!supabase || !session) {
      return;
    }
    let active = true;
    void Promise.resolve(
      supabase
        .from("admin_users")
        .select("user_id")
        .eq("user_id", session.user.id)
        .maybeSingle(),
    )
      .then(({ data, error: membershipError }) => {
        if (!active) return;
        if (membershipError) {
          setAuthError(`Could not check admin access: ${membershipError.message}`);
          setIsAdmin(false);
          return;
        }
        setIsAdmin(Boolean(data));
      })
      .catch((reason: unknown) => {
        if (!active) return;
        setAuthError(
          `Could not check admin access: ${reason instanceof Error ? reason.message : "unknown error"}`,
        );
        setIsAdmin(false);
      });
    return () => {
      active = false;
    };
  }, [session]);

  useEffect(() => {
    if (!supabase || !session || !isAdmin) return;
    let active = true;
    void (async () => {
      setSyncing(true);
      const [{ data, error: catalogueError }, { data: imported, error: pdfError }] =
        await Promise.all([
          supabase
            .from("catalogue_versions")
            .select("channel, content")
            .in("channel", ["draft", "published"]),
          supabase
            .from("pdf_imports")
            .select("id, original_filename, storage_path, extracted_text, page_count, created_at")
            .order("created_at", { ascending: false })
            .limit(100),
        ]);
      if (!active) return;
      if (catalogueError) {
        setError(`Could not load the cloud catalogue: ${catalogueError.message}`);
      } else {
        const cloudDraft = data?.find((row) => row.channel === "draft");
        const published = data?.find((row) => row.channel === "published");
        const selected = cloudDraft ?? published;
        if (selected) {
          try {
            const cloudCatalogue = validateCatalogue(selected.content);
            const localSnapshot = getCatalogueSnapshot();
            const localCatalogue = validateCatalogue(JSON.parse(localSnapshot));
            const localDiffers =
              localSnapshot !== EMPTY_CATALOGUE &&
              stableJson(localCatalogue) !== stableJson(cloudCatalogue);
            const replaceLocal =
              !localDiffers ||
              window.confirm(
                "A different local draft is saved in this browser. Replace it with the cloud catalogue? Choose Cancel to keep the local draft.",
              );
            if (replaceLocal) {
              updateCatalogue(cloudCatalogue);
              setNotice(
                cloudDraft
                  ? "Cloud draft loaded."
                  : "Published catalogue loaded.",
              );
            } else {
              setNotice(
                "Kept the different local draft. Saving it to cloud will replace the current cloud draft.",
              );
            }
            setCloudChannel(cloudDraft ? "draft" : "published");
          } catch (reason) {
            setError(
              `The saved cloud catalogue is invalid: ${reason instanceof Error ? reason.message : "unknown format"}`,
            );
          }
        }
      }
      if (pdfError) {
        setError((current) =>
          [current, `Could not load PDF imports: ${pdfError.message}`]
            .filter(Boolean)
            .join(" "),
        );
      } else {
        setPdfImports((imported ?? []) as PdfImport[]);
      }
      setSyncing(false);
    })().catch((reason: unknown) => {
      if (active) {
        setError(
          `Could not load cloud data: ${reason instanceof Error ? reason.message : "unknown error"}`,
        );
        setSyncing(false);
      }
    });
    return () => {
      active = false;
    };
  }, [isAdmin, session]);

  const filteredHymns = useMemo(() => {
    const search = query.trim().toLowerCase();
    return catalogue.hymns.filter((hymn) => {
      const matchesLanguage = language === "all" || hymn.language === language;
      const matchesSearch =
        !search ||
        [hymn.number, hymn.title, hymn.id, hymn.author ?? ""]
          .join(" ")
          .toLowerCase()
          .includes(search);
      return matchesLanguage && matchesSearch;
    });
  }, [catalogue.hymns, language, query]);

  const languageCounts = useMemo(
    () => ({
      english: catalogue.hymns.filter((hymn) => hymn.language === "english").length,
      twi: catalogue.hymns.filter((hymn) => hymn.language === "twi").length,
    }),
    [catalogue.hymns],
  );

  function openNewHymn(source?: PdfImport) {
    setError("");
    setEditingId(null);
    const sourceText = source?.extracted_text ?? "";
    const firstLine = sourceText.split(/\r?\n/).find((line) => line.trim()) ?? "";
    const filename = source?.original_filename.replace(/\.pdf$/i, "") ?? "";
    const id = `${source?.original_filename ?? ""}-${crypto.randomUUID().slice(0, 8)}`
      .toLowerCase()
      .replace(/[^a-z0-9-]+/g, "-")
      .replace(/^-|-$/g, "");
    setDraft({
      ...emptyDraft(),
      id,
      title: (firstLine || filename).slice(0, 120),
      source: source?.original_filename,
      stanzasText: sourceText,
    });
  }

  function openEditHymn(hymn: Hymn) {
    setError("");
    setEditingId(hymn.id);
    setDraft(toDraft(hymn));
    setMenuId(null);
  }

  function closeEditor() {
    setDraft(null);
    setEditingId(null);
    setError("");
  }

  function updateDraft(field: keyof HymnDraft, value: string) {
    setDraft((current) =>
      current ? { ...current, [field]: value } : current,
    );
  }

  function saveHymn(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!draft) return;
    setError("");

    const id = draft.id.trim();
    if (!id) {
      setError("Add a stable ID before saving.");
      return;
    }
    if (
      catalogue.hymns.some(
        (hymn) => hymn.id === id && hymn.id !== editingId,
      )
    ) {
      setError("That ID is already used by another hymn.");
      return;
    }

    let recordings: Recording[];
    try {
      const parsed: unknown = JSON.parse(draft.recordingsText || "[]");
      if (
        !Array.isArray(parsed) ||
        parsed.some(
          (item) =>
            !item ||
            typeof item !== "object" ||
            typeof item.id !== "string" ||
            typeof item.type !== "string" ||
            !RECORDING_TYPES.includes(item.type),
        )
      ) {
        throw new Error("Use an array of recordings with valid IDs and types.");
      }
      recordings = parsed as Recording[];
    } catch (reason) {
      setError(
        reason instanceof SyntaxError
          ? "Recordings must be valid JSON."
          : reason instanceof Error
            ? reason.message
            : "Could not read recordings.",
      );
      return;
    }

    const hymn: Hymn = {
      id,
      number: draft.number.trim(),
      title: draft.title.trim(),
      language: draft.language,
      stanzas: draft.stanzasText
        .split(/\n\s*\n/)
        .map((stanza) => stanza.trim())
        .filter(Boolean),
      recordings,
      ...Object.fromEntries(
        [
          "chorus",
          "author",
          "composer",
          "source",
          "copyright",
          "attribution",
          "permission",
          "artwork",
        ].flatMap((field) => {
          const value = draft[field as keyof HymnDraft];
          return typeof value === "string" && value.trim()
            ? [[field, value.trim()]]
            : [];
        }),
      ),
    };

    let nextCatalogue: Catalogue;
    try {
      const current = validateCatalogue(JSON.parse(getCatalogueSnapshot()));
      nextCatalogue = validateCatalogue({
        ...current,
        hymns: editingId
          ? current.hymns.map((item) => (item.id === editingId ? hymn : item))
          : [...current.hymns, hymn],
      });
    } catch (reason) {
      setError(
        reason instanceof Error ? reason.message : "Hymn entry is invalid.",
      );
      return;
    }
    updateCatalogue(nextCatalogue);
    setNotice(editingId ? "Hymn changes saved." : "Hymn added to the catalogue.");
    closeEditor();
  }

  function deleteHymn(hymn: Hymn) {
    if (!window.confirm(`Remove “${hymn.title}” from this draft catalogue?`)) {
      setMenuId(null);
      return;
    }
    updateCatalogue((current) => ({
      ...current,
      hymns: current.hymns.filter((item) => item.id !== hymn.id),
    }));
    setNotice("Hymn removed from the draft catalogue.");
    setMenuId(null);
  }

  async function importCatalogue(event: ChangeEvent<HTMLInputElement>) {
    const file = event.target.files?.[0];
    event.target.value = "";
    if (!file) return;
    setError("");
    setNotice("");
    try {
      const imported = validateCatalogue(JSON.parse(await file.text()));
      updateCatalogue(imported);
      setNotice(`Imported ${imported.hymns.length} hymns from ${file.name}.`);
    } catch (reason) {
      setError(
        reason instanceof Error
          ? `Import failed: ${reason.message}`
          : "Import failed: the file could not be read.",
      );
    }
  }

  function exportCatalogue() {
    const data = `${JSON.stringify(catalogue, null, 2)}\n`;
    const url = URL.createObjectURL(
      new Blob([data], { type: "application/json" }),
    );
    const link = document.createElement("a");
    link.href = url;
    link.download = "catalogue.json";
    link.click();
    URL.revokeObjectURL(url);
    setNotice("Catalogue JSON exported.");
  }

  async function signIn(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!supabase) return;
    setSigningIn(true);
    setAuthError("");
    try {
      const { error: signInError } = await supabase.auth.signInWithPassword({
        email,
        password,
      });
      if (signInError) setAuthError(`Sign-in failed: ${signInError.message}`);
    } catch (reason) {
      setAuthError(
        `Sign-in failed: ${reason instanceof Error ? reason.message : "unknown error"}`,
      );
    } finally {
      setSigningIn(false);
    }
  }

  async function signOut() {
    if (!supabase) return;
    try {
      const { error: signOutError } = await supabase.auth.signOut();
      if (signOutError) {
        setAuthError(`Sign-out failed: ${signOutError.message}`);
        return;
      }
      setSession(null);
      setIsAdmin(null);
    } catch (reason) {
      setAuthError(
        `Sign-out failed: ${reason instanceof Error ? reason.message : "unknown error"}`,
      );
    }
  }

  async function saveToCloud(channel: "draft" | "published") {
    if (!supabase || !session) return;
    setError("");
    setNotice("");
    let content: Catalogue;
    try {
      content = validateCatalogue(catalogue);
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : "Catalogue is invalid.");
      return;
    }
    if (
      channel === "published" &&
      !window.confirm(
        `Publish ${content.hymns.length} hymns to the mobile app? This replaces the currently published catalogue.`,
      )
    ) {
      return;
    }
    setSyncing(true);
    try {
      const { error: saveError } = await supabase
        .from("catalogue_versions")
        .upsert(
          {
            channel,
            content,
            updated_at: new Date().toISOString(),
            updated_by: session.user.id,
          },
          { onConflict: "channel" },
        );
      if (saveError) {
        setError(`Could not ${channel === "draft" ? "save the draft" : "publish"}: ${saveError.message}`);
        return;
      }
      if (channel === "published") {
        const { error: draftError } = await supabase
          .from("catalogue_versions")
          .upsert(
            {
              channel: "draft",
              content,
              updated_at: new Date().toISOString(),
              updated_by: session.user.id,
            },
            { onConflict: "channel" },
          );
        if (draftError) {
          setCloudChannel("published");
          setError(
            `Catalogue was published, but its draft copy could not be refreshed: ${draftError.message}`,
          );
          return;
        }
      }
      setCloudChannel(channel);
      setNotice(
        channel === "draft"
          ? "Draft saved to Supabase. It is not visible in the app yet."
          : "Catalogue published. The app will sync it the next time it is online.",
      );
    } catch (reason) {
      setError(
        `Cloud operation failed: ${reason instanceof Error ? reason.message : "unknown error"}`,
      );
    } finally {
      setSyncing(false);
    }
  }

  async function importPdfs(event: ChangeEvent<HTMLInputElement>) {
    const files = Array.from(event.target.files ?? []);
    event.target.value = "";
    if (!files.length) return;
    if (!supabase || !session) {
      setError("Sign in to Supabase to store PDF sources.");
      return;
    }
    if (files.some((file) => file.type !== "application/pdf" && !file.name.toLowerCase().endsWith(".pdf"))) {
      setError("Only PDF files can be uploaded.");
      return;
    }
    setUploadingPdfs(true);
    setError("");
    setNotice("");
    const failures: string[] = [];
    let importedCount = 0;
    for (const file of files) {
      if (file.size > 50 * 1024 * 1024) {
        failures.push(`${file.name}: exceeds the 50 MB limit.`);
        continue;
      }
      let storagePath = "";
      try {
        const { text, pageCount } = await extractPdfText(file);
        storagePath = `${session.user.id}/${crypto.randomUUID()}-${file.name.replace(/[^a-zA-Z0-9._-]/g, "_")}`;
        const { error: uploadError } = await supabase.storage
          .from("source-pdfs")
          .upload(storagePath, file, {
            contentType: "application/pdf",
            upsert: false,
          });
        if (uploadError) throw new Error(`Private PDF upload failed: ${uploadError.message}`);
        const { data, error: insertError } = await supabase
          .from("pdf_imports")
          .insert({
            uploaded_by: session.user.id,
            original_filename: file.name,
            storage_path: storagePath,
            extracted_text: text,
            page_count: pageCount,
          })
          .select("id, original_filename, storage_path, extracted_text, page_count, created_at")
          .single();
        if (insertError) {
          const { error: cleanupError } = await supabase.storage
            .from("source-pdfs")
            .remove([storagePath]);
          throw new Error(
            `Could not save import record: ${insertError.message}${cleanupError ? `; source cleanup failed: ${cleanupError.message}` : ""}`,
          );
        }
        setPdfImports((current) => [data as PdfImport, ...current]);
        importedCount += 1;
      } catch (reason) {
        failures.push(
          `${file.name}: ${reason instanceof Error ? reason.message : "import failed"}`,
        );
      }
    }
    setUploadingPdfs(false);
    if (failures.length) {
      setError(
        `${importedCount} PDF(s) imported; ${failures.length} failed. ${failures.join(" ")}`,
      );
    } else {
      setNotice(`${importedCount} PDF(s) uploaded and text extracted for review.`);
    }
  }

  async function downloadSourcePdf(item: PdfImport) {
    if (!supabase) return;
    setError("");
    try {
      const { data, error: downloadError } = await supabase.storage
        .from("source-pdfs")
        .download(item.storage_path);
      if (downloadError) {
        setError(`Could not download ${item.original_filename}: ${downloadError.message}`);
        return;
      }
      const url = URL.createObjectURL(data);
      const link = document.createElement("a");
      link.href = url;
      link.download = item.original_filename;
      link.click();
      window.setTimeout(() => URL.revokeObjectURL(url), 1000);
    } catch (reason) {
      setError(
        `Could not download ${item.original_filename}: ${reason instanceof Error ? reason.message : "unknown error"}`,
      );
    }
  }

  if (supabase && !authReady) {
    return <div className="auth-screen"><p>Checking your admin session…</p></div>;
  }

  if (supabase && !session) {
    return (
      <main className="auth-screen">
        <form className="auth-card" onSubmit={signIn}>
          <span className="brand-mark"><Icon name="music" size={22} /></span>
          <div className="eyebrow">PCG HYMNS CONTENT STUDIO</div>
          <h1>Admin sign in</h1>
          <p>Sign in with an account that has been granted catalogue admin access.</p>
          <label>Email<input required type="email" autoComplete="username" value={email} onChange={(event) => setEmail(event.target.value)} /></label>
          <label>Password<input required type="password" autoComplete="current-password" value={password} onChange={(event) => setPassword(event.target.value)} /></label>
          {authError && <div className="alert error-alert" role="alert">{authError}</div>}
          <button className="button primary" disabled={signingIn}>{signingIn ? "Signing in…" : "Sign in"}</button>
          <small>Admin accounts are provisioned by the Supabase project owner.</small>
        </form>
      </main>
    );
  }

  if (supabase && isAdmin === null) {
    return <div className="auth-screen"><p>Verifying admin access…</p></div>;
  }

  if (supabase && !isAdmin) {
    return (
      <main className="auth-screen">
        <div className="auth-card">
          <span className="brand-mark"><Icon name="music" size={22} /></span>
          <h1>Admin access required</h1>
          <p>This signed-in account has not been added to the catalogue admin list.</p>
          {authError && <div className="alert error-alert" role="alert">{authError}</div>}
          <button className="button secondary" onClick={signOut}>Sign out</button>
        </div>
      </main>
    );
  }

  return (
    <div className="dashboard">
      <aside className="sidebar">
        <a className="brand" href="#" aria-label="PCG Hymns admin home">
          <span className="brand-mark"><Icon name="music" size={22} /></span>
          <span className="brand-copy"><strong>PCG Hymns</strong><small>CONTENT STUDIO</small></span>
        </a>
        <div className="nav-label">WORKSPACE</div>
        <nav aria-label="Workspace">
          <a className="nav-item active" href="#catalogue">
            <Icon name="book" size={19} /> <span>Catalogue</span>
            <span className="nav-count">{catalogue.hymns.length}</span>
          </a>
        </nav>
        <div className="sidebar-bottom">
          <div className="offline-card">
            <span className="status-dot" />
            <div><strong>Local workspace</strong><span>Drafts stay in this browser</span></div>
          </div>
          <div className="sidebar-foot">PCG HYMNBOOK ADMIN <span>v1.0</span></div>
        </div>
      </aside>

      <main className="main-content" id="catalogue">
        <header className="topbar">
          <div className="breadcrumb">Workspace <span>/</span> <strong>Catalogue</strong></div>
          <div className="topbar-right">
            <span className="save-state"><span className="status-dot" />{supabase ? cloudChannel === "published" ? "Published version loaded" : cloudChannel === "draft" ? "Cloud draft loaded" : "Local draft" : "Local-only mode"}</span>
            {session ? (
              <>
                <span className="account-email">{session.user.email}</span>
                <button className="text-button signout-button" onClick={signOut}>Sign out</button>
              </>
            ) : <span className="avatar" aria-label="Local administrator">A</span>}
          </div>
        </header>

        <div className="page-content">
          <section className="page-heading">
            <div>
              <div className="eyebrow">CONTENT MANAGEMENT</div>
              <h1>Hymn catalogue</h1>
              <p>Manage verified hymns and prepare your catalogue for release.</p>
            </div>
            <div className="heading-actions">
              <input
                ref={fileInput}
                className="visually-hidden"
                type="file"
                accept=".json,application/json"
                aria-label="Choose catalogue JSON to import"
                onChange={importCatalogue}
              />
              <button className="button secondary" onClick={() => fileInput.current?.click()}>
                <Icon name="upload" size={17} /> Import JSON
              </button>
              <button
                className="button primary"
                onClick={exportCatalogue}
                title="Download the current catalogue as JSON"
              >
                <Icon name="download" size={17} /> Export catalogue
              </button>
            </div>
          </section>

          {!supabase && (
            <div className="alert setup-alert" role="status">
              Supabase is not configured yet. You can edit a local draft, but sign-in, cloud publishing, and private PDF storage will be enabled after project setup.
            </div>
          )}
          {supabase && isAdmin && (
            <div className="cloud-toolbar">
              <span>{syncing ? "Syncing with Supabase…" : "Cloud catalogue"}</span>
              <div>
                <button className="button secondary" disabled={syncing} onClick={() => void saveToCloud("draft")}>Save draft to cloud</button>
                <button className="button primary" disabled={syncing} onClick={() => void saveToCloud("published")}>Publish to app</button>
              </div>
            </div>
          )}

          <section className="stats-grid" aria-label="Catalogue summary">
            <article className="stat-card">
              <div className="stat-top"><span>Total hymns</span><span className="stat-icon violet"><Icon name="book" size={18} /></span></div>
              <strong>{catalogue.hymns.length}</strong>
              <small>in current catalogue</small>
            </article>
            <article className="stat-card">
              <div className="stat-top"><span>English</span><span className="language-dot english-dot" /></div>
              <strong>{languageCounts.english}</strong>
              <small>English entries</small>
            </article>
            <article className="stat-card">
              <div className="stat-top"><span>Twi</span><span className="language-dot twi-dot" /></div>
              <strong>{languageCounts.twi}</strong>
              <small>Twi entries</small>
            </article>
            <article className="stat-card">
              <div className="stat-top"><span>Recordings</span><span className="stat-icon peach"><Icon name="music" size={18} /></span></div>
              <strong>{catalogue.hymns.reduce((count, hymn) => count + (hymn.recordings?.length ?? 0), 0)}</strong>
              <small>linked audio versions</small>
            </article>
          </section>

          <section className="catalogue-panel pdf-panel">
            <div className="panel-heading">
              <div><h2>PDF source library <span className="title-count">{pdfImports.length}</span></h2><p>Upload selectable-text PDFs in batches; each file is kept in private storage for reference</p></div>
              <div>
                <input
                  ref={pdfInput}
                  className="visually-hidden"
                  type="file"
                  accept="application/pdf,.pdf"
                  multiple
                  aria-label="Choose PDF source files"
                  disabled={!supabase || !isAdmin || uploadingPdfs}
                  onChange={importPdfs}
                />
                <button
                  className="button secondary"
                  disabled={!supabase || !isAdmin || uploadingPdfs}
                  onClick={() => pdfInput.current?.click()}
                  title={!supabase ? "Configure Supabase to upload private PDF sources" : "Select multiple PDFs"}
                >
                  <Icon name="upload" size={17} /> {uploadingPdfs ? "Extracting and uploading…" : "Upload PDFs"}
                </button>
              </div>
            </div>
            <div className="pdf-guidance">
              PDF text is extracted in your browser before upload. Scanned/image-only PDFs need OCR and are not supported yet. All extracted text is a draft source—review wording, boundaries, numbering, and permissions before saving or publishing.
            </div>
            {pdfImports.length > 0 ? (
              <div className="pdf-import-list">
                {pdfImports.map((item) => (
                  <article className="pdf-import-item" key={item.id}>
                    <div className="pdf-file-icon">PDF</div>
                    <div className="pdf-import-info">
                      <strong>{item.original_filename}</strong>
                      <small>{item.page_count} pages · {new Date(item.created_at).toLocaleDateString()}</small>
                    </div>
                    <details className="pdf-text-details">
                      <summary>Review extracted text</summary>
                      <pre>{item.extracted_text}</pre>
                    </details>
                    <button className="text-button download-source-button" onClick={() => void downloadSourcePdf(item)}>Download PDF</button>
                    <button className="button secondary use-pdf-button" onClick={() => openNewHymn(item)}>Create draft hymn</button>
                  </article>
                ))}
              </div>
            ) : (
              <div className="pdf-empty">
                {supabase && isAdmin ? "No PDF sources uploaded yet." : "Connect Supabase and sign in as an admin to upload source PDFs."}
              </div>
            )}
          </section>

          <section className="catalogue-panel">
            <div className="panel-heading">
              <div><h2>All hymns <span className="title-count">{filteredHymns.length}</span></h2><p>Verified content ready for your app catalogue</p></div>
              <button className="button primary add-button" onClick={() => openNewHymn()}>
                <Icon name="plus" size={17} /> Add hymn
              </button>
            </div>
            <div className="table-toolbar">
              <label className="search-box">
                <Icon name="search" size={18} />
                <input
                  type="search"
                  placeholder="Search by title, number or author..."
                  value={query}
                  onChange={(event) => setQuery(event.target.value)}
                />
                <kbd>/</kbd>
              </label>
              <label className="filter-select">
                <span className="visually-hidden">Filter by language</span>
                <select value={language} onChange={(event) => setLanguage(event.target.value)}>
                  <option value="all">All languages</option>
                  <option value="english">English</option>
                  <option value="twi">Twi</option>
                </select>
              </label>
            </div>

            {storageError && <div className="alert error-alert" role="alert">{storageError}</div>}
            {error && !draft && <div className="alert error-alert" role="alert">{error}<button onClick={() => setError("")} aria-label="Dismiss error">×</button></div>}
            {notice && <div className="alert success-alert" role="status">{notice}<button onClick={() => setNotice("")} aria-label="Dismiss message">×</button></div>}

            <div className="table-wrap">
              <table>
                <thead>
                  <tr><th>HYMN</th><th>LANGUAGE</th><th>STANZAS</th><th>RECORDINGS</th><th>ATTRIBUTION</th><th><span className="visually-hidden">Actions</span></th></tr>
                </thead>
                <tbody>
                  {filteredHymns.map((hymn) => (
                    <tr key={hymn.id}>
                      <td>
                        <div className="hymn-cell">
                          <span className={`hymn-number ${hymn.language}`}>{hymn.number}</span>
                          <span className="hymn-info"><strong>{hymn.title}</strong><small>{hymn.author || hymn.id}</small></span>
                        </div>
                      </td>
                      <td><span className={`language-pill ${hymn.language}`}>{hymn.language === "english" ? "English" : "Twi"}</span></td>
                      <td><span className="plain-value">{hymn.stanzas.length}</span></td>
                      <td><span className="recording-cell"><Icon name="music" size={15} /> {hymn.recordings?.length ?? 0}</span></td>
                      <td><span className={`permission-status ${hymn.permission ? "complete" : "missing"}`}><span />{hymn.permission ? "Permission noted" : "Needs review"}</span></td>
                      <td className="actions-cell">
                        <button className="icon-button" aria-label={`Edit ${hymn.title}`} onClick={() => openEditHymn(hymn)}>Edit</button>
                        <div className="menu-wrap">
                          <button className="icon-button more-button" aria-label={`More actions for ${hymn.title}`} onClick={() => setMenuId(menuId === hymn.id ? null : hymn.id)}><Icon name="more" /></button>
                          {menuId === hymn.id && <div className="action-menu"><button onClick={() => openEditHymn(hymn)}>Edit hymn</button><button className="delete-action" onClick={() => deleteHymn(hymn)}>Remove hymn</button></div>}
                        </div>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
              {filteredHymns.length === 0 && (
                <div className="empty-state">
                  <span className="empty-icon"><Icon name={query || language !== "all" ? "search" : "book"} size={24} /></span>
                  <h3>{catalogue.hymns.length === 0 ? "Your catalogue is ready for content" : "No hymns found"}</h3>
                  <p>{catalogue.hymns.length === 0 ? "Import your existing catalogue.json or add a verified hymn to get started." : "Try another search or clear the language filter."}</p>
                  {catalogue.hymns.length === 0 ? <button className="button primary" onClick={() => openNewHymn()}><Icon name="plus" size={17} /> Add your first hymn</button> : <button className="text-button" onClick={() => { setQuery(""); setLanguage("all"); }}>Clear filters</button>}
                </div>
              )}
            </div>
            <footer className="table-footer">
              <span>Showing <strong>{filteredHymns.length}</strong> of <strong>{catalogue.hymns.length}</strong> hymns</span>
              <span className="footer-note"><span className="status-dot" /> Changes save automatically in this browser</span>
            </footer>
          </section>

          <div className="content-note">
            <span className="note-mark">i</span>
            <p><strong>Content verification matters.</strong> Only add text and recordings that have been verified and cleared for distribution. Export your catalogue to <code>assets/catalogue.json</code> when it’s ready to publish.</p>
          </div>
        </div>
      </main>

      {draft && (
        <div className="modal-backdrop" onMouseDown={(event) => { if (event.target === event.currentTarget) closeEditor(); }}>
          <section className="editor-modal" role="dialog" aria-modal="true" aria-labelledby="editor-title">
            <header className="modal-header">
              <div><div className="eyebrow">CATALOGUE ENTRY</div><h2 id="editor-title">{editingId ? "Edit hymn" : "Add a hymn"}</h2></div>
              <button className="close-button" aria-label="Close editor" onClick={closeEditor}>×</button>
            </header>
            <form onSubmit={saveHymn}>
              <div className="form-body">
                {draft.source && (
                  <div className="pdf-guidance editor-pdf-guidance">
                    Source: {draft.source}. This creates one hymn entry. If this PDF contains a whole book, copy one hymn&apos;s text at a time from the PDF source preview and create separate entries.
                  </div>
                )}
                <div className="form-grid">
                  <label>Stable ID <span className="required">*</span><input required value={draft.id} disabled={Boolean(editingId)} placeholder="english-001" onChange={(event) => updateDraft("id", event.target.value)} /></label>
                  <label>Hymn number <span className="required">*</span><input required value={draft.number} placeholder="001" onChange={(event) => updateDraft("number", event.target.value)} /></label>
                  <label className="full-field">Title <span className="required">*</span><input required value={draft.title} placeholder="Verified title" onChange={(event) => updateDraft("title", event.target.value)} /></label>
                  <label>Language <span className="required">*</span><select value={draft.language} onChange={(event) => updateDraft("language", event.target.value)}><option value="english">English</option><option value="twi">Twi</option></select></label>
                  <label>Author<input value={draft.author ?? ""} placeholder="Author name" onChange={(event) => updateDraft("author", event.target.value)} /></label>
                  <label>Composer<input value={draft.composer ?? ""} placeholder="Composer name" onChange={(event) => updateDraft("composer", event.target.value)} /></label>
                  <label>Source<input value={draft.source ?? ""} placeholder="Verified source" onChange={(event) => updateDraft("source", event.target.value)} /></label>
                  <label className="full-field">Stanzas<textarea rows={6} value={draft.stanzasText} placeholder={"Enter one stanza at a time, separated by a blank line.\nPreserve line breaks within each stanza."} onChange={(event) => updateDraft("stanzasText", event.target.value)} /></label>
                  <label className="full-field">Chorus<textarea rows={3} value={draft.chorus ?? ""} placeholder="Optional verified chorus" onChange={(event) => updateDraft("chorus", event.target.value)} /></label>
                  <label>Copyright<input value={draft.copyright ?? ""} placeholder="Copyright notice" onChange={(event) => updateDraft("copyright", event.target.value)} /></label>
                  <label>Artwork URL<input value={draft.artwork ?? ""} placeholder="https://..." onChange={(event) => updateDraft("artwork", event.target.value)} /></label>
                  <label className="full-field">Attribution<input value={draft.attribution ?? ""} placeholder="Required attribution" onChange={(event) => updateDraft("attribution", event.target.value)} /></label>
                  <label className="full-field">Permission details<input value={draft.permission ?? ""} placeholder="Permission or licence details" onChange={(event) => updateDraft("permission", event.target.value)} /></label>
                  <label className="full-field">Recordings (JSON)<textarea className="code-input" rows={6} spellCheck={false} value={draft.recordingsText} onChange={(event) => updateDraft("recordingsText", event.target.value)} /><small className="field-hint">Use an array of recording objects. Supported types: {RECORDING_TYPES.join(", ")}.</small></label>
                </div>
                {error && <div className="alert error-alert" role="alert">{error}</div>}
              </div>
              <footer className="modal-footer">
                <button type="button" className="button secondary" onClick={closeEditor}>Cancel</button>
                <button type="submit" className="button primary">{editingId ? "Save changes" : "Add hymn"}</button>
              </footer>
            </form>
          </section>
        </div>
      )}
    </div>
  );
}
