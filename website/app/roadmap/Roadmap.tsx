import {
  type CSSProperties,
  type DragEvent,
  type FocusEvent,
  type KeyboardEvent,
  useState,
} from "react";

import { WINDOWS } from "~/catwm/script";

import { AREAS, type Card, COLUMNS, type Column, type Edit } from "./model";

const REPO_URL = "https://github.com/noxaur/CatWM";

const hueOf = (area: string) => WINDOWS[AREAS[area] ?? "sky"].color;

type Drop = { column: Column; before?: string };

// The four columns. With onMove the cards drag between and inside the columns,
// with onOpen a click opens the card, and with onAdd each column has a + to type a new card.
export function Columns({
  cards,
  selected,
  onMove,
  onOpen,
  onAdd,
}: {
  cards: Card[];
  selected?: string;
  onMove?: (id: string, column: Column, before?: string) => void;
  onOpen?: (card: Card) => void;
  onAdd?: (column: Column, title: string, before?: string) => void;
}) {
  const [drop, setDrop] = useState<Drop | null>(null);
  const [dragging, setDragging] = useState<string | null>(null);
  // The card at the top when the + was pressed. New cards go above it, in the order typed.
  const [adding, setAdding] = useState<Drop | null>(null);

  const over = (column: Column) => (e: DragEvent<HTMLElement>) => {
    if (!onMove || !dragging) return;
    e.preventDefault();
    const items = [...e.currentTarget.querySelectorAll<HTMLElement>("[data-card]")];
    const next = items.find((el) => {
      const r = el.getBoundingClientRect();
      return r.top + r.height / 2 > e.clientY;
    });
    const before = next?.dataset.card;
    if (drop?.column !== column || drop.before !== before) setDrop({ column, before });
  };

  const leave = (e: DragEvent<HTMLElement>) => {
    if (!e.currentTarget.contains(e.relatedTarget as Node | null)) setDrop(null);
  };

  const land = (column: Column) => (e: DragEvent<HTMLElement>) => {
    e.preventDefault();
    const id = e.dataTransfer.getData("text/plain");
    if (id && id !== drop?.before) onMove?.(id, column, drop?.before);
    setDrop(null);
  };

  return (
    <div className="columns">
      {COLUMNS.map(({ id, name }) => {
        const list = cards.filter((c) => c.column === id);
        const mark = drop?.column === id;
        return (
          <section
            key={id}
            className="column"
            aria-label={name}
            onDragOver={over(id)}
            onDragLeave={leave}
            onDrop={land(id)}
          >
            <h2 className="column__head">
              {onAdd && (
                <button
                  type="button"
                  className="icon-button icon-button--small"
                  aria-label={`Add a card to ${name}`}
                  onClick={() => setAdding({ column: id, before: list[0]?.id })}
                >
                  <svg viewBox="0 0 12 12" aria-hidden="true">
                    <path d="M6 1.5v9M1.5 6h9" />
                  </svg>
                </button>
              )}
              {name}
              <span className="column__count">{list.length}</span>
            </h2>
            <ul className="column__list">
              {adding?.column === id && onAdd && (
                <li>
                  <QuickAdd
                    onAdd={(title) => onAdd(id, title, adding.before)}
                    onDone={() => setAdding(null)}
                  />
                </li>
              )}
              {list.map((card) => (
                <li key={card.id} data-card={card.id}>
                  {mark && drop.before === card.id && <span className="drop-line" />}
                  <CardView
                    card={card}
                    onOpen={onOpen}
                    selected={card.id === selected}
                    dragging={card.id === dragging}
                    onDrag={onMove && setDragging}
                  />
                </li>
              ))}
              {mark && !drop.before && <li className="drop-line" />}
              {list.length === 0 && !mark && adding?.column !== id && (
                <li className="column__empty">Nothing here</li>
              )}
            </ul>
          </section>
        );
      })}
    </div>
  );
}

// Type a title and press Return to add a card at the top of the column. It stays open for the
// next card. Esc, or leaving it empty, closes it.
function QuickAdd({ onAdd, onDone }: { onAdd: (title: string) => void; onDone: () => void }) {
  return (
    <input
      className="quick-add"
      placeholder="Card title, then Return"
      aria-label="New card title"
      autoFocus
      onKeyDown={(e) => {
        const title = e.currentTarget.value.trim();
        if (e.key === "Enter" && title) {
          onAdd(title);
          e.currentTarget.value = "";
        } else if (e.key === "Escape") onDone();
      }}
      onBlur={(e) => {
        if (!e.currentTarget.value.trim()) onDone();
      }}
    />
  );
}

function CardView({
  card,
  onOpen,
  selected,
  dragging,
  onDrag,
}: {
  card: Card;
  onOpen?: (card: Card) => void;
  selected: boolean;
  dragging: boolean;
  onDrag?: (id: string | null) => void;
}) {
  const open = onOpen && (() => onOpen(card));
  return (
    <article
      className="bcard"
      draggable={!!onDrag}
      data-selected={selected || undefined}
      data-dragging={dragging || undefined}
      onDragStart={(e) => {
        e.dataTransfer.setData("text/plain", card.id);
        e.dataTransfer.effectAllowed = "move";
        onDrag?.(card.id);
      }}
      onDragEnd={() => onDrag?.(null)}
      onClick={open}
      onKeyDown={(e) => {
        if (open && (e.key === "Enter" || e.key === " ")) {
          e.preventDefault();
          open();
        }
      }}
      role={open ? "button" : undefined}
      tabIndex={open ? 0 : undefined}
    >
      <h3 className="bcard__title">{card.title}</h3>
      {card.line && <p className="bcard__line">{card.line}</p>}
      {card.questionable && card.note && <p className="bcard__note">{card.note}</p>}
      <p className="bcard__meta">
        <span className="bcard__area" style={{ "--hue": hueOf(card.area) } as CSSProperties}>
          {card.area}
        </span>
        {card.ref && <Ref value={card.ref} />}
      </p>
    </article>
  );
}

function Ref({ value, className = "bcard__ref" }: { value: string; className?: string }) {
  const number = /^#(\d+)$/.exec(value)?.[1];
  if (!number) return <span className={className}>{value}</span>;
  return (
    <a
      className={className}
      href={`${REPO_URL}/issues/${number}`}
      target="_blank"
      rel="noreferrer"
      onClick={(e) => e.stopPropagation()}
    >
      {value}
    </a>
  );
}

type Text = "title" | "line" | "note" | "ref";

// The open card, beside the columns. Each field saves when you leave it, and each choice
// saves when you make it. Return leaves a one-line field, Esc closes the panel.
export function CardPanel({
  card,
  onEdit,
  onClose,
}: {
  card: Card;
  onEdit: (edit: Edit) => void;
  onClose: () => void;
}) {
  const [confirm, setConfirm] = useState(false);
  const patch = (p: Partial<Card>) => onEdit({ intent: "save", card: { ...card, ...p } });

  const text = (k: Text) => ({
    defaultValue: card[k] ?? "",
    onBlur: (e: FocusEvent<HTMLInputElement | HTMLTextAreaElement>) => {
      const v = e.currentTarget.value.trim();
      if (v === (card[k] ?? "")) return;
      if (k === "title" && !v) e.currentTarget.value = card.title;
      else patch({ [k]: k === "note" || k === "ref" ? v || undefined : v });
    },
  });
  const keys = (e: KeyboardEvent<HTMLElement>) => {
    if (e.key === "Enter" && e.currentTarget.tagName === "INPUT") e.currentTarget.blur();
    if (e.key === "Escape") {
      e.currentTarget.blur();
      onClose();
    }
  };

  return (
    <aside className="panel" aria-label="Card" onKeyDown={keys}>
      <header className="panel__head">
        <button type="button" className="icon-button" aria-label="Close" onClick={onClose}>
          <svg viewBox="0 0 12 12" aria-hidden="true">
            <path d="M2 2l8 8M10 2l-8 8" />
          </svg>
        </button>
        <code className="panel__id" title="Write Roadmap: and this id in a PR">
          {card.id}
        </code>
        {card.ref && <Ref value={card.ref} className="panel__ref" />}
      </header>

      <textarea
        className="ifield ifield--title"
        aria-label="Title"
        rows={1}
        {...text("title")}
        onKeyDown={(e) => {
          if (e.key === "Enter") {
            e.preventDefault();
            e.currentTarget.blur();
          }
        }}
      />
      <textarea
        className="ifield"
        aria-label="Line"
        placeholder="One line about what the user gets"
        rows={2}
        {...text("line")}
      />

      <Pills
        label="Column"
        options={COLUMNS.map((c) => [c.id, c.name])}
        value={card.column}
        onPick={(column) => patch({ column })}
      />
      <Pills
        label="Area"
        options={Object.keys(AREAS).map((a) => [a, a])}
        value={card.area}
        onPick={(area) => patch({ area })}
        hue
      />

      <label className="panel__row">
        Questionable
        <input
          type="checkbox"
          className="sr-only"
          checked={!!card.questionable}
          onChange={(e) => patch({ questionable: e.target.checked || undefined })}
        />
        <span className="switch" data-on={card.questionable || undefined} aria-hidden="true" />
      </label>

      <div className="panel__group">
        <span className="panel__label">Note for developers</span>
        <textarea
          className="ifield"
          aria-label="Note"
          placeholder="Why it is here, or what is left"
          rows={3}
          {...text("note")}
        />
      </div>
      <div className="panel__group">
        <span className="panel__label">Issue, PR or branch</span>
        <input
          className="ifield ifield--mono"
          aria-label="Ref"
          placeholder="#123"
          {...text("ref")}
        />
      </div>

      <footer className="panel__foot">
        <button
          type="button"
          className="button button--danger"
          onClick={() => {
            if (!confirm) return setConfirm(true);
            onEdit({ intent: "remove", id: card.id });
            onClose();
          }}
          onBlur={() => setConfirm(false)}
        >
          {confirm ? "Remove for good" : "Remove"}
        </button>
      </footer>
    </aside>
  );
}

function Pills<T extends string>({
  label,
  options,
  value,
  onPick,
  hue = false,
}: {
  label: string;
  options: [T, string][];
  value: T;
  onPick: (value: T) => void;
  hue?: boolean;
}) {
  return (
    <div className="panel__group">
      <span className="panel__label">{label}</span>
      <div className="pills" role="radiogroup" aria-label={label}>
        {options.map(([v, name]) => (
          <button
            key={v}
            type="button"
            role="radio"
            className="tab tab--small"
            aria-checked={v === value}
            onClick={() => v !== value && onPick(v)}
          >
            {hue && <span className="pills__dot" style={{ "--hue": hueOf(v) } as CSSProperties} />}
            {name}
          </button>
        ))}
      </div>
    </div>
  );
}
