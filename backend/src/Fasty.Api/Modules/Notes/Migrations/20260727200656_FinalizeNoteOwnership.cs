using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Fasty.Api.Modules.Notes.Migrations
{
    /// <inheritdoc />
    public partial class FinalizeNoteOwnership : Migration
    {
        /// <inheritdoc />
        protected override void Up(
            MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(
                """
                DO $$
                BEGIN
                    IF EXISTS
                    (
                        SELECT 1
                        FROM notes.notes
                        WHERE "UserId" IS NULL
                    )
                    THEN
                        RAISE EXCEPTION
                            'Cannot finalize note ownership: unowned notes still exist.';
                    END IF;
                END
                $$;
                """);

            migrationBuilder.AlterColumn<Guid>(
                name: "UserId",
                schema: "notes",
                table: "notes",
                type: "uuid",
                nullable: false,
                oldClrType: typeof(Guid),
                oldType: "uuid",
                oldNullable: true);
        }

        /// <inheritdoc />
        protected override void Down(
            MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AlterColumn<Guid>(
                name: "UserId",
                schema: "notes",
                table: "notes",
                type: "uuid",
                nullable: true,
                oldClrType: typeof(Guid),
                oldType: "uuid");
        }
    }
}