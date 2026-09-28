export type RepoMissionType  = 'simple' | 'npc_hostile' | 'pvp' | 'stealth'
export type RepoOrderStatus  = 'available' | 'active' | 'completed' | 'failed' | 'expired'

export interface RepoOrder {
  id:                      number
  vehicle_plate:           string
  vehicle_model:           string
  vehicle_value:           number
  vehicle_owner_citizenid: string | null  // null = NPC owner
  mission_type:            RepoMissionType
  location_zone:           string         // zone name; coords revealed in Sub-spec 2
  payment:                 number
  status:                  RepoOrderStatus
  expires_at_unix:         number         // unix timestamp
  created_at_unix:         number         // unix timestamp
}
