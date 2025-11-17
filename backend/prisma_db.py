from backend.prisma_client import Prisma

db = Prisma(auto_register=True)

async def get_db():
    if not db.is_connected():
        await db.connect()
    return db
