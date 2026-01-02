'use client';

import { useState, useRef, useEffect, KeyboardEvent, DragEvent } from 'react';
import { colors } from '@/lib/colors';

// v226: Suggestion chip with label (display) and command (sent to AI)
interface SuggestionChip {
  label: string;
  command: string;
}

// v254: Attached file for vision/import
export interface AttachedFile {
  file: File;
  preview: string;  // Data URL for image preview
  type: 'image' | 'csv';
}

interface ChatInputProps {
  onSend: (message: string, attachments?: AttachedFile[]) => void;
  isLoading: boolean;
  suggestions?: SuggestionChip[];
}

// Helper to read file as data URL
function readAsDataURL(file: File): Promise<string> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(reader.result as string);
    reader.onerror = reject;
    reader.readAsDataURL(file);
  });
}

export default function ChatInput({ onSend, isLoading, suggestions = [] }: ChatInputProps) {
  const [input, setInput] = useState('');
  const [showPlusMenu, setShowPlusMenu] = useState(false);
  const [attachedFiles, setAttachedFiles] = useState<AttachedFile[]>([]);
  const [isDragging, setIsDragging] = useState(false);

  const textareaRef = useRef<HTMLTextAreaElement>(null);
  const plusMenuRef = useRef<HTMLDivElement>(null);
  const imageInputRef = useRef<HTMLInputElement>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);
  const dropZoneRef = useRef<HTMLDivElement>(null);

  // Close plus menu when clicking outside
  useEffect(() => {
    function handleClickOutside(event: MouseEvent) {
      if (plusMenuRef.current && !plusMenuRef.current.contains(event.target as Node)) {
        setShowPlusMenu(false);
      }
    }
    if (showPlusMenu) {
      document.addEventListener('mousedown', handleClickOutside);
      return () => document.removeEventListener('mousedown', handleClickOutside);
    }
  }, [showPlusMenu]);

  // Auto-resize textarea
  useEffect(() => {
    const textarea = textareaRef.current;
    if (textarea) {
      textarea.style.height = 'auto';
      textarea.style.height = `${Math.min(textarea.scrollHeight, 200)}px`;
    }
  }, [input]);

  // v254: Process selected files
  const processFiles = async (files: FileList | File[]) => {
    const fileArray = Array.from(files);

    for (const file of fileArray) {
      // Check file size (max 10MB)
      if (file.size > 10 * 1024 * 1024) {
        console.warn('File too large:', file.name);
        continue;
      }

      if (file.type.startsWith('image/')) {
        const preview = await readAsDataURL(file);
        setAttachedFiles(prev => [...prev, { file, preview, type: 'image' }]);
      } else if (file.name.endsWith('.csv')) {
        setAttachedFiles(prev => [...prev, { file, preview: '', type: 'csv' }]);
      }
    }
  };

  // v254: Handle file selection from input
  const handleFileSelect = async (e: React.ChangeEvent<HTMLInputElement>) => {
    if (e.target.files?.length) {
      await processFiles(e.target.files);
    }
    // Reset input so same file can be selected again
    e.target.value = '';
  };

  // v254: Remove attachment
  const removeAttachment = (index: number) => {
    setAttachedFiles(prev => prev.filter((_, i) => i !== index));
  };

  // v254: Drag and drop handlers
  const handleDragEnter = (e: DragEvent) => {
    e.preventDefault();
    e.stopPropagation();
    setIsDragging(true);
  };

  const handleDragLeave = (e: DragEvent) => {
    e.preventDefault();
    e.stopPropagation();
    // Only set dragging to false if we're leaving the drop zone entirely
    if (!dropZoneRef.current?.contains(e.relatedTarget as Node)) {
      setIsDragging(false);
    }
  };

  const handleDragOver = (e: DragEvent) => {
    e.preventDefault();
    e.stopPropagation();
  };

  const handleDrop = async (e: DragEvent) => {
    e.preventDefault();
    e.stopPropagation();
    setIsDragging(false);

    if (e.dataTransfer.files?.length) {
      await processFiles(e.dataTransfer.files);
    }
  };

  const handleSubmit = () => {
    const trimmed = input.trim();
    const hasAttachments = attachedFiles.length > 0;

    // Allow send if there's text OR attachments
    if ((!trimmed && !hasAttachments) || isLoading) return;

    onSend(trimmed, hasAttachments ? attachedFiles : undefined);
    setInput('');
    setAttachedFiles([]);

    // Reset textarea height
    if (textareaRef.current) {
      textareaRef.current.style.height = 'auto';
    }
  };

  const handleKeyDown = (e: KeyboardEvent<HTMLTextAreaElement>) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      handleSubmit();
    }
  };

  const handleChipClick = (chip: SuggestionChip) => {
    if (isLoading) return;
    onSend(chip.command);
  };

  const canSend = (input.trim() || attachedFiles.length > 0) && !isLoading;

  return (
    <div
      ref={dropZoneRef}
      className="border-t border-gray-200 bg-white relative"
      onDragEnter={handleDragEnter}
      onDragOver={handleDragOver}
      onDragLeave={handleDragLeave}
      onDrop={handleDrop}
    >
      {/* v254: Drag overlay */}
      {isDragging && (
        <div className="absolute inset-0 bg-blue-50/90 border-2 border-dashed border-blue-400 rounded-lg flex items-center justify-center z-50 pointer-events-none">
          <div className="text-center">
            <svg className="w-12 h-12 mx-auto text-blue-500 mb-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M7 16a4 4 0 01-.88-7.903A5 5 0 1115.9 6L16 6a5 5 0 011 9.9M15 13l-3-3m0 0l-3 3m3-3v12" />
            </svg>
            <p className="text-blue-600 font-medium">Drop files to import</p>
            <p className="text-blue-500 text-sm">Images or CSV files</p>
          </div>
        </div>
      )}

      {/* Hidden file inputs */}
      <input
        ref={imageInputRef}
        type="file"
        accept="image/*"
        multiple
        onChange={handleFileSelect}
        className="hidden"
      />
      <input
        ref={fileInputRef}
        type="file"
        accept=".csv,.xlsx,.xls"
        onChange={handleFileSelect}
        className="hidden"
      />

      {/* Suggestion chips */}
      {!isLoading && suggestions.length > 0 && attachedFiles.length === 0 && (
        <div className="px-4 pt-3 pb-2">
          <div className="flex gap-2 overflow-x-auto scrollbar-hide">
            {suggestions.map((chip, index) => (
              <button
                key={index}
                onClick={() => handleChipClick(chip)}
                className="flex-shrink-0 px-3 py-1.5 text-sm text-gray-600 bg-gray-100 hover:bg-gray-200 rounded-full transition-colors whitespace-nowrap"
              >
                {chip.label}
              </button>
            ))}
          </div>
        </div>
      )}

      {/* v254: Attachment preview */}
      {attachedFiles.length > 0 && (
        <div className="px-4 pt-3">
          <div className="max-w-3xl mx-auto">
            <div className="flex gap-2 flex-wrap">
              {attachedFiles.map((attached, index) => (
                <div key={index} className="relative group">
                  {attached.type === 'image' ? (
                    <div className="relative">
                      <img
                        src={attached.preview}
                        alt={attached.file.name}
                        className="w-20 h-20 object-cover rounded-lg border border-gray-200"
                      />
                      <div className="absolute inset-0 bg-black/40 opacity-0 group-hover:opacity-100 rounded-lg transition-opacity" />
                    </div>
                  ) : (
                    <div className="w-20 h-20 bg-gray-100 rounded-lg border border-gray-200 flex flex-col items-center justify-center p-2">
                      <svg className="w-8 h-8 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z" />
                      </svg>
                      <span className="text-xs text-gray-500 truncate w-full text-center mt-1">
                        {attached.file.name.length > 10
                          ? attached.file.name.slice(0, 7) + '...'
                          : attached.file.name}
                      </span>
                    </div>
                  )}
                  {/* Remove button */}
                  <button
                    onClick={() => removeAttachment(index)}
                    className="absolute -top-2 -right-2 w-6 h-6 bg-red-500 hover:bg-red-600 text-white rounded-full flex items-center justify-center shadow-md transition-colors opacity-0 group-hover:opacity-100"
                    title="Remove"
                  >
                    <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
                    </svg>
                  </button>
                </div>
              ))}
            </div>
          </div>
        </div>
      )}

      {/* Input area */}
      <div className="px-4 py-3">
        <div className="max-w-3xl mx-auto">
          <div className="flex items-end gap-2 bg-gray-100 rounded-2xl px-4 py-2">
            {/* Plus button with popover menu */}
            <div className="relative" ref={plusMenuRef}>
              <button
                type="button"
                onClick={() => setShowPlusMenu(!showPlusMenu)}
                className="flex-shrink-0 p-2 text-gray-400 hover:text-gray-600 transition-colors"
                title="Add attachment"
              >
                <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 4v16m8-8H4" />
                </svg>
              </button>

              {/* v254: Redesigned plus menu - Photos & Files */}
              {showPlusMenu && (
                <div className="absolute bottom-full left-0 mb-2 w-48 bg-white rounded-xl shadow-lg border border-gray-200 py-1 z-50">
                  <button
                    onClick={() => {
                      setShowPlusMenu(false);
                      imageInputRef.current?.click();
                    }}
                    className="w-full flex items-center gap-3 px-4 py-2.5 text-sm text-gray-700 hover:bg-gray-50 transition-colors"
                  >
                    <svg className="w-5 h-5 text-green-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z" />
                    </svg>
                    Photos
                  </button>
                  <button
                    onClick={() => {
                      setShowPlusMenu(false);
                      fileInputRef.current?.click();
                    }}
                    className="w-full flex items-center gap-3 px-4 py-2.5 text-sm text-gray-700 hover:bg-gray-50 transition-colors"
                  >
                    <svg className="w-5 h-5 text-orange-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z" />
                    </svg>
                    Files
                  </button>
                </div>
              )}
            </div>

            {/* Text input */}
            <textarea
              ref={textareaRef}
              value={input}
              onChange={(e) => setInput(e.target.value)}
              onKeyDown={handleKeyDown}
              placeholder={attachedFiles.length > 0 ? "Add a message about these files..." : "Message Medina..."}
              rows={1}
              disabled={isLoading}
              className="flex-1 bg-transparent border-0 resize-none focus:outline-none text-gray-800 placeholder-gray-400 py-2 max-h-[200px]"
            />

            {/* Voice button (future: voice input) */}
            <button
              type="button"
              className="flex-shrink-0 p-2 text-gray-400 hover:text-gray-600 transition-colors"
              title="Voice input"
            >
              <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 11a7 7 0 01-7 7m0 0a7 7 0 01-7-7m7 7v4m0 0H8m4 0h4m-4-8a3 3 0 01-3-3V5a3 3 0 116 0v6a3 3 0 01-3 3z" />
              </svg>
            </button>

            {/* Send button */}
            <button
              onClick={handleSubmit}
              disabled={!canSend}
              className="flex-shrink-0 p-2 rounded-full transition-colors"
              style={{
                backgroundColor: canSend ? colors.accentBlue : '#d1d5db',
                color: canSend ? 'white' : '#6b7280',
                cursor: canSend ? 'pointer' : 'not-allowed',
              }}
              title="Send message"
            >
              {isLoading ? (
                <svg className="w-5 h-5 animate-spin" fill="none" viewBox="0 0 24 24">
                  <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" />
                  <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z" />
                </svg>
              ) : (
                <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 19l9 2-9-18-9 18 9-2zm0 0v-8" />
                </svg>
              )}
            </button>
          </div>

          {/* Helper text */}
          <p className="text-xs text-gray-400 text-center mt-2">
            {attachedFiles.length > 0
              ? `${attachedFiles.length} file${attachedFiles.length > 1 ? 's' : ''} attached. Press Enter to send.`
              : 'Press Enter to send, Shift+Enter for new line'
            }
          </p>
        </div>
      </div>
    </div>
  );
}
