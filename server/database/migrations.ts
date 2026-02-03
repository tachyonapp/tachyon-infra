import { join } from "path";

export interface MigrationFile {
  filename: string;
  version: string;
  description: string;
  path: string;
}

export const MIGRATIONS: MigrationFile[] = [
  {
    filename: "001_initial_schema.sql",
    version: "001",
    description: "Initial APPI compliant schema with encrypted PII fields",
    path: join(__dirname, "001_initial_schema.sql"),
  },
  // Add more migration files here as needed
];
