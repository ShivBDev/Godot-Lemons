using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Backend.Migrations
{
    /// <inheritdoc />
    public partial class InitialLemonsSchema : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "OtpCodes",
                columns: table => new
                {
                    emailHash = table.Column<string>(type: "text", nullable: false),
                    codeHash = table.Column<string>(type: "text", nullable: false),
                    expiresAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_OtpCodes", x => x.emailHash);
                });

            migrationBuilder.CreateTable(
                name: "Players",
                columns: table => new
                {
                    emailHash = table.Column<string>(type: "text", nullable: false),
                    name = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: false),
                    money = table.Column<float>(type: "real", nullable: false),
                    dayCount = table.Column<int>(type: "integer", nullable: false),
                    lemonStock = table.Column<int>(type: "integer", nullable: false),
                    sugarStock = table.Column<int>(type: "integer", nullable: false),
                    iceStock = table.Column<int>(type: "integer", nullable: false),
                    recipeLemons = table.Column<int>(type: "integer", nullable: false),
                    recipeSugar = table.Column<int>(type: "integer", nullable: false),
                    recipeIce = table.Column<int>(type: "integer", nullable: false),
                    salePrice = table.Column<float>(type: "real", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_Players", x => x.emailHash);
                });

            migrationBuilder.CreateTable(
                name: "PlayerSessions",
                columns: table => new
                {
                    tokenHash = table.Column<string>(type: "text", nullable: false),
                    emailHash = table.Column<string>(type: "text", nullable: false),
                    expiresAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_PlayerSessions", x => x.tokenHash);
                });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "OtpCodes");

            migrationBuilder.DropTable(
                name: "Players");

            migrationBuilder.DropTable(
                name: "PlayerSessions");
        }
    }
}
