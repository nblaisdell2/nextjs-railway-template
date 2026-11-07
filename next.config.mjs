/** @type {import('next').NextConfig} */
const nextConfig = {
  // Produces a minimal, self-contained server build in .next/standalone
  // that the Docker image copies and runs.
  output: "standalone",
  reactStrictMode: true,
};

export default nextConfig;
