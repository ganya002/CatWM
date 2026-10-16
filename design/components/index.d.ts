/** Ouch design system components. window.Ouch */
type SF = string; // an SF Symbol name, e.g. "rectangle.split.3x1"
type Effect = 'bounce' | 'wiggle' | 'rotate' | 'pulse' | 'breathe' | 'variable' | 'replace' | 'draw' | 'appear' | 'scale';
type Key = string; // 'cmd' | 'opt' | 'shift' | 'ctrl' | 'caps' | 'return' | 'esc' | letter
export interface SymbolProps { name: SF; effect?: Effect; trigger?: unknown; size?: number; weight?: 'ultralight' | 'light' | 'regular' | 'medium' | 'semibold' | 'bold'; repeat?: 'loop'; label?: string; color?: string; }
export interface KbdProps { keys: Key[]; then?: Key[][]; size?: 'lg'; pressed?: boolean; }
export interface ButtonProps { variant?: 'primary' | 'secondary' | 'ghost' | 'danger'; size?: 'sm' | 'lg'; icon?: SF; iconEffect?: Effect; iconTrigger?: unknown; shortcut?: Key[]; label?: string; disabled?: boolean; onClick?: () => void; children?: any; }
export interface SwitchProps { checked?: boolean; defaultChecked?: boolean; onChange?: (on: boolean) => void; label: string; }
export interface SliderProps { min?: number; max?: number; step?: number; value?: number; defaultValue?: number; resetValue?: number; onChange?: (v: number) => void; label?: string; format?: (v: number) => string; ticks?: number | number[]; variant?: 'line' | 'bar'; symbol?: SF; symbolEffect?: Effect; bare?: boolean; showValue?: boolean; width?: number; }
export interface SegmentedProps { options: (string | { value: string; label: string; symbol?: SF })[]; value?: string; defaultValue?: string; onChange?: (v: string) => void; label?: string; }
export interface RowProps { label: string; description?: string; symbol?: SF; control?: any; children?: any; }
export interface GroupProps { title?: string; footer?: string; children: any; }
export interface SurfaceProps { tone?: 'accent'; density?: 'xs' | 'sm' | 'md' | 'lg' | 'xl'; glass?: boolean; caret?: 'top' | 'bottom' | 'left' | 'none'; caretAt?: number; lead?: SF | any; leadEffect?: Effect; kicker?: string; done?: boolean; headEnd?: any; onClose?: () => void; title?: any; body?: any; keys?: any; actions?: any; progress?: number; children?: any; }
export interface MenuItem { type?: 'item' | 'check' | 'radio' | 'switch' | 'sub' | 'label' | 'sep' | 'custom' | 'footer' | 'search'; id?: string; label?: string; symbol?: SF; effect?: Effect; shortcut?: Key[]; value?: string; checked?: boolean; group?: string; danger?: boolean; disabled?: boolean; hidden?: boolean; keywords?: string; items?: MenuItem[]; width?: number; render?: (ctx: any) => any; placeholder?: string; }
export interface MenuProps { items: MenuItem[]; glass?: boolean; onSelect?: (item: MenuItem) => void; openIndex?: number; highlight?: number; subHighlight?: number; query?: string; autoFocus?: boolean; }
export interface CommandMenuProps extends MenuProps { placeholder?: string; shortcut?: Key[]; width?: number; }
export interface TooltipProps { label: string; keys?: Key[]; then?: Key[][]; side?: 'bottom' | 'top' | 'right'; delay?: number; open?: boolean; children?: any; }
export interface CoachMarkProps { step?: number; total?: number; kicker?: string; title: any; body?: any; keys?: Key[]; pressed?: boolean; done?: boolean; doneText?: string; hint?: string; onNext?: () => void; onBack?: () => void; onSkip?: () => void; nextLabel?: string; caret?: 'top' | 'bottom' | 'left'; caretAt?: number; tone?: 'plain'; glass?: boolean; }
export interface HUDProps { layout?: string; label?: string; keys?: Key[]; hint?: string; warning?: boolean; pop?: number; }
export interface LayoutThumbProps { layout: string; width?: number; height?: number; selected?: boolean; }
export interface WorkspaceStripProps { count?: number; current?: number; occupied?: number[]; onPick?: (n: number) => void; }
export interface LayoutPickerProps { value?: string; defaultValue?: string; onChange?: (layout: string) => void; columns?: number; thumb?: number; }
