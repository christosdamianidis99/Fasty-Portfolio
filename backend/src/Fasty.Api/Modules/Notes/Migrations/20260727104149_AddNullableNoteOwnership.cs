using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Fasty.Api.Modules.Notes.Migrations
{
    /// <inheritdoc />
    public partial class AddNullableNoteOwnership : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "IX_notes_UpdatedAt",
                schema: "notes",
                table: "notes");

            migrationBuilder.AddColumn<Guid>(
                name: "UserId",
                schema: "notes",
                table: "notes",
                type: "uuid",
                nullable: true);

            migrationBuilder.CreateIndex(
                name: "IX_notes_UserId_UpdatedAt",
                schema: "notes",
                table: "notes",
                columns: new[] { "UserId", "UpdatedAt" });

            migrationBuilder.AddForeignKey(
                name: "FK_notes_users_UserId",
                schema: "notes",
                table: "notes",
                column: "UserId",
                principalSchema: "auth",
                principalTable: "users",
                principalColumn: "Id",
                onDelete: ReferentialAction.Cascade);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "FK_notes_users_UserId",
                schema: "notes",
                table: "notes");

            migrationBuilder.DropIndex(
                name: "IX_notes_UserId_UpdatedAt",
                schema: "notes",
                table: "notes");

            migrationBuilder.DropColumn(
                name: "UserId",
                schema: "notes",
                table: "notes");

            migrationBuilder.CreateIndex(
                name: "IX_notes_UpdatedAt",
                schema: "notes",
                table: "notes",
                column: "UpdatedAt");
        }
    }
}
