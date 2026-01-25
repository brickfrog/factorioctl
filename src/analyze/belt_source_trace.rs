//! Belt source tracing - trace upstream to find item sources
//!
//! Traces belt networks upstream to identify all entities that can
//! place items onto a belt, including handling of circular loops.

use std::collections::{HashMap, HashSet};
use serde::{Deserialize, Serialize};

use crate::world::{Direction, Entity, TilePos};
use super::BeltGraph;

/// Type of entity that can be a source of items on a belt
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub enum ItemSourceType {
    /// Mining drill outputting to belt
    MiningDrill,
    /// Inserter placing items on belt
    Inserter,
    /// Belt feeding into this belt
    Belt,
    /// Splitter output
    Splitter,
    /// Underground belt exit
    UndergroundBeltExit,
    /// Assembling machine or other crafter outputting via inserter
    Assembler,
    /// Unknown source type
    Unknown,
}

/// A source of items that can feed a belt
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ItemSource {
    /// Position of the source entity
    pub position: TilePos,
    /// Type of source
    pub source_type: ItemSourceType,
    /// Entity name (e.g., "burner-mining-drill", "inserter")
    pub entity_name: String,
    /// Unit number if available
    pub unit_number: Option<u32>,
    /// Which lane this source feeds (1=left, 2=right, None=both/unknown)
    pub target_lane: Option<u8>,
    /// Item types this source can provide (if known)
    pub possible_items: Vec<String>,
    /// For inserters: what entity they pick up from
    pub pickup_from: Option<Box<ItemSource>>,
}

/// Result of tracing sources for a belt position
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BeltSourceTraceResult {
    /// Starting position for the trace
    pub origin: TilePos,
    /// Sources that feed the left lane
    pub left_lane_sources: Vec<ItemSource>,
    /// Sources that feed the right lane
    pub right_lane_sources: Vec<ItemSource>,
    /// Sources that can feed both lanes
    pub both_lane_sources: Vec<ItemSource>,
    /// All item types that can appear on this belt
    pub possible_items: Vec<String>,
    /// Number of belt segments traced
    pub traced_belt_count: u32,
    /// True if this belt is part of a loop
    pub is_loop: bool,
    /// Belt positions forming the loop (if any)
    pub loop_path: Option<Vec<TilePos>>,
}

/// Trace sources for a belt at the given position
pub fn trace_belt_sources(
    origin: TilePos,
    graph: &BeltGraph,
    entities: &[Entity],
) -> Option<BeltSourceTraceResult> {
    // Check that there's a belt at the origin
    if !graph.contains(&origin) {
        return None;
    }

    // Build entity lookup map by position
    let entity_map: HashMap<TilePos, Vec<&Entity>> = build_entity_map(entities);

    // Track visited belts and detect loops
    let mut visited: HashSet<TilePos> = HashSet::new();
    let mut path: Vec<TilePos> = Vec::new();
    let mut loop_path: Option<Vec<TilePos>> = None;

    // Collect all belt positions that feed into origin (upstream traversal)
    let mut upstream_belts: HashSet<TilePos> = HashSet::new();
    collect_upstream_belts(origin, graph, &mut visited, &mut path, &mut loop_path, &mut upstream_belts);

    let is_loop = loop_path.is_some();

    // Find all non-belt sources that can feed into the traced belt network
    let mut left_lane_sources = Vec::new();
    let mut right_lane_sources = Vec::new();
    let mut both_lane_sources = Vec::new();
    let mut all_possible_items: HashSet<String> = HashSet::new();

    // Check each upstream belt position for feeding entities
    for belt_pos in &upstream_belts {
        if let Some(belt_node) = graph.get(belt_pos) {
            // Find entities that can feed this belt position
            let sources = find_sources_for_belt(*belt_pos, belt_node.direction, &entity_map, graph);

            for source in sources {
                // Collect possible items
                for item in &source.possible_items {
                    all_possible_items.insert(item.clone());
                }

                // Categorize by target lane
                match source.target_lane {
                    Some(1) => left_lane_sources.push(source),
                    Some(2) => right_lane_sources.push(source),
                    _ => both_lane_sources.push(source),
                }
            }
        }
    }

    // For looped belts, all sources can potentially reach any position
    if is_loop {
        // Move all lane-specific sources to "both" since items circulate
        both_lane_sources.extend(left_lane_sources.drain(..));
        both_lane_sources.extend(right_lane_sources.drain(..));
    }

    Some(BeltSourceTraceResult {
        origin,
        left_lane_sources,
        right_lane_sources,
        both_lane_sources,
        possible_items: all_possible_items.into_iter().collect(),
        traced_belt_count: upstream_belts.len() as u32,
        is_loop,
        loop_path,
    })
}

/// Build a map of entity positions for quick lookup
fn build_entity_map(entities: &[Entity]) -> HashMap<TilePos, Vec<&Entity>> {
    let mut map: HashMap<TilePos, Vec<&Entity>> = HashMap::new();
    for entity in entities {
        let pos = entity.position.to_tile();
        map.entry(pos).or_default().push(entity);
    }
    map
}

/// Recursively collect all upstream belt positions
fn collect_upstream_belts(
    pos: TilePos,
    graph: &BeltGraph,
    visited: &mut HashSet<TilePos>,
    path: &mut Vec<TilePos>,
    loop_path: &mut Option<Vec<TilePos>>,
    upstream_belts: &mut HashSet<TilePos>,
) {
    if visited.contains(&pos) {
        // Check if this is a loop back to current path
        if let Some(loop_start_idx) = path.iter().position(|p| *p == pos) {
            if loop_path.is_none() {
                *loop_path = Some(path[loop_start_idx..].to_vec());
            }
        }
        return;
    }

    visited.insert(pos);
    path.push(pos);
    upstream_belts.insert(pos);

    // Recursively visit upstream belts
    for upstream_pos in graph.upstream_of(&pos) {
        collect_upstream_belts(*upstream_pos, graph, visited, path, loop_path, upstream_belts);
    }

    path.pop();
}

/// Find entities that can feed items onto a specific belt position
fn find_sources_for_belt(
    belt_pos: TilePos,
    belt_direction: Direction,
    entity_map: &HashMap<TilePos, Vec<&Entity>>,
    graph: &BeltGraph,
) -> Vec<ItemSource> {
    let mut sources = Vec::new();

    // Check all adjacent positions for feeding entities
    let adjacent_positions = [
        belt_pos.offset_in_direction(Direction::North),
        belt_pos.offset_in_direction(Direction::East),
        belt_pos.offset_in_direction(Direction::South),
        belt_pos.offset_in_direction(Direction::West),
    ];

    for adj_pos in &adjacent_positions {
        if let Some(entities) = entity_map.get(adj_pos) {
            for entity in entities {
                // Skip belts - they're handled by the graph
                if entity.name.contains("belt") {
                    continue;
                }

                if let Some(source) = entity_to_source(entity, belt_pos, belt_direction) {
                    sources.push(source);
                }
            }
        }
    }

    // Also check the belt position itself (for items placed directly, like from drills)
    if let Some(entities) = entity_map.get(&belt_pos) {
        for entity in entities {
            if !entity.name.contains("belt") {
                if let Some(source) = entity_to_source(entity, belt_pos, belt_direction) {
                    sources.push(source);
                }
            }
        }
    }

    // Check positions that might have inserters reaching this belt
    // Inserters typically have pickup range of 1 tile behind and drop 1 tile ahead
    let inserter_search_positions: Vec<TilePos> = [
        belt_pos.offset_in_direction_by(Direction::North, 1),
        belt_pos.offset_in_direction_by(Direction::East, 1),
        belt_pos.offset_in_direction_by(Direction::South, 1),
        belt_pos.offset_in_direction_by(Direction::West, 1),
    ]
    .to_vec();

    for search_pos in inserter_search_positions {
        if let Some(entities) = entity_map.get(&search_pos) {
            for entity in entities {
                if entity.name.contains("inserter") {
                    // Check if this inserter drops onto our belt
                    let inserter_dir = Direction::from_factorio(entity.direction);
                    let drop_pos = search_pos.offset_in_direction(inserter_dir);

                    if drop_pos == belt_pos {
                        let lane = determine_inserter_lane(search_pos, belt_pos, belt_direction);
                        sources.push(ItemSource {
                            position: search_pos,
                            source_type: ItemSourceType::Inserter,
                            entity_name: entity.name.clone(),
                            unit_number: entity.unit_number,
                            target_lane: lane,
                            possible_items: vec![], // Would need inventory analysis
                            pickup_from: None, // Would need recursive lookup
                        });
                    }
                }
            }
        }
    }

    sources
}

/// Convert an entity to an ItemSource if it can feed belts
fn entity_to_source(
    entity: &Entity,
    belt_pos: TilePos,
    belt_direction: Direction,
) -> Option<ItemSource> {
    let entity_pos = entity.position.to_tile();
    let entity_type = entity.entity_type.as_deref().unwrap_or("");

    match entity_type {
        "mining-drill" => {
            // Mining drills output in their facing direction
            let drill_dir = Direction::from_factorio(entity.direction);
            let output_pos = entity_pos.offset_in_direction(drill_dir);

            if output_pos == belt_pos {
                // Determine which lane based on position relative to belt
                let lane = determine_output_lane(entity_pos, belt_pos, belt_direction);

                Some(ItemSource {
                    position: entity_pos,
                    source_type: ItemSourceType::MiningDrill,
                    entity_name: entity.name.clone(),
                    unit_number: entity.unit_number,
                    target_lane: lane,
                    possible_items: vec![], // Would need to check what resource is under the drill
                    pickup_from: None,
                })
            } else {
                None
            }
        }
        "inserter" => {
            // Already handled in find_sources_for_belt
            None
        }
        "splitter" => {
            Some(ItemSource {
                position: entity_pos,
                source_type: ItemSourceType::Splitter,
                entity_name: entity.name.clone(),
                unit_number: entity.unit_number,
                target_lane: None, // Splitters output to both lanes
                possible_items: vec![],
                pickup_from: None,
            })
        }
        "underground-belt" => {
            // Check if this is an exit (output mode)
            let ub_dir = Direction::from_factorio(entity.direction);
            let output_pos = entity_pos.offset_in_direction(ub_dir);

            if output_pos == belt_pos {
                Some(ItemSource {
                    position: entity_pos,
                    source_type: ItemSourceType::UndergroundBeltExit,
                    entity_name: entity.name.clone(),
                    unit_number: entity.unit_number,
                    target_lane: None,
                    possible_items: vec![],
                    pickup_from: None,
                })
            } else {
                None
            }
        }
        _ => None,
    }
}

/// Determine which lane an output hits based on position relative to belt direction
fn determine_output_lane(
    source_pos: TilePos,
    belt_pos: TilePos,
    belt_direction: Direction,
) -> Option<u8> {
    // The "left" lane (line 1) is on the left side when facing the belt direction
    // The "right" lane (line 2) is on the right side

    let dx = source_pos.x - belt_pos.x;
    let dy = source_pos.y - belt_pos.y;

    match belt_direction {
        Direction::North => {
            // Belt going north (up), left is west (-x), right is east (+x)
            if dx < 0 { Some(1) } else if dx > 0 { Some(2) } else { None }
        }
        Direction::East => {
            // Belt going east (right), left is north (-y), right is south (+y)
            if dy < 0 { Some(1) } else if dy > 0 { Some(2) } else { None }
        }
        Direction::South => {
            // Belt going south (down), left is east (+x), right is west (-x)
            if dx > 0 { Some(1) } else if dx < 0 { Some(2) } else { None }
        }
        Direction::West => {
            // Belt going west (left), left is south (+y), right is north (-y)
            if dy > 0 { Some(1) } else if dy < 0 { Some(2) } else { None }
        }
        _ => None, // Diagonal directions not typically used for belts
    }
}

/// Determine which lane an inserter drops to
fn determine_inserter_lane(
    inserter_pos: TilePos,
    belt_pos: TilePos,
    belt_direction: Direction,
) -> Option<u8> {
    // Same logic as determine_output_lane
    determine_output_lane(inserter_pos, belt_pos, belt_direction)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_determine_output_lane_north() {
        let belt_pos = TilePos::new(5, 5);
        let belt_dir = Direction::North;

        // Source from west -> left lane
        assert_eq!(
            determine_output_lane(TilePos::new(4, 5), belt_pos, belt_dir),
            Some(1)
        );
        // Source from east -> right lane
        assert_eq!(
            determine_output_lane(TilePos::new(6, 5), belt_pos, belt_dir),
            Some(2)
        );
        // Source from same x -> neither specific lane
        assert_eq!(
            determine_output_lane(TilePos::new(5, 6), belt_pos, belt_dir),
            None
        );
    }

    #[test]
    fn test_determine_output_lane_east() {
        let belt_pos = TilePos::new(5, 5);
        let belt_dir = Direction::East;

        // Source from north -> left lane
        assert_eq!(
            determine_output_lane(TilePos::new(5, 4), belt_pos, belt_dir),
            Some(1)
        );
        // Source from south -> right lane
        assert_eq!(
            determine_output_lane(TilePos::new(5, 6), belt_pos, belt_dir),
            Some(2)
        );
    }
}
