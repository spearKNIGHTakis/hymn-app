import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "PCG Hymns | Content Studio",
  description: "Manage and prepare verified hymn catalogue content.",
};

export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    <html lang="en" suppressHydrationWarning>
      <body suppressHydrationWarning>{children}</body>
    </html>
  );
}
